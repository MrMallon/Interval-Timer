import AVFoundation
import os

/// Generates beeps and ticks in real time, so the app needs no audio files.
///
/// The source node renders continuously (silence between tones). That keeps
/// the audio session genuinely playing while a workout runs, which is what
/// lets the timer keep running and cueing on a locked screen.
final class ToneSynth {
    struct Tone {
        var frequency: Double
        var duration: Double
        var amplitude: Float
        /// Seconds of silence before this tone starts (for multi-beep patterns).
        var delay: Double = 0
        /// Overtones as (frequency ratio, relative level). Empty = a pure sine.
        var partials: [Partial] = []
        /// Exponential fade time constant in seconds (bells, soft tones). nil = steady.
        var decay: Double? = nil
    }

    struct Partial: Sendable {
        var ratio: Double
        var level: Float
    }

    private struct Voice {
        var frequency: Double
        var amplitude: Float
        var totalFrames: Int
        var framesLeft: Int
        var delayFrames: Int
        var partials: [Partial]
        var decayFrames: Double?
    }

    private let state = OSAllocatedUnfairLock(initialState: [Voice]())
    private(set) var sampleRate: Double = 44_100

    func configure(sampleRate: Double) {
        self.sampleRate = sampleRate
    }

    func play(_ tones: [Tone]) {
        let rate = sampleRate
        let voices = tones.map { tone in
            let frames = max(1, Int(tone.duration * rate))
            return Voice(
                frequency: tone.frequency,
                amplitude: tone.amplitude,
                totalFrames: frames,
                framesLeft: frames,
                delayFrames: Int(tone.delay * rate),
                partials: tone.partials.isEmpty ? [Partial(ratio: 1, level: 1)] : Self.normalized(tone.partials),
                decayFrames: tone.decay.map { $0 * rate }
            )
        }
        state.withLockUnchecked { $0.append(contentsOf: voices) }
    }

    /// Scales overtone levels so a rich tone is no louder than a pure one.
    private static func normalized(_ partials: [Partial]) -> [Partial] {
        let total = partials.reduce(Float(0)) { $0 + abs($1.level) }
        guard total > 0 else { return partials }
        return partials.map { Partial(ratio: $0.ratio, level: $0.level / total) }
    }

    func stopAll() {
        state.withLockUnchecked { $0.removeAll() }
    }

    /// Called on the real-time audio thread.
    func render(frameCount: Int, into buffers: UnsafeMutableAudioBufferListPointer) {
        let rate = sampleRate
        let attackFrames = Int(0.004 * rate)
        let releaseFrames = Int(0.012 * rate)

        state.withLockUnchecked { voices in
            for buffer in buffers {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for frame in 0..<frameCount { data[frame] = 0 }
            }
            guard !voices.isEmpty else { return }

            for index in voices.indices {
                var voice = voices[index]
                let omega = 2 * Double.pi * voice.frequency / rate
                for frame in 0..<frameCount {
                    if voice.delayFrames > 0 {
                        voice.delayFrames -= 1
                        continue
                    }
                    guard voice.framesLeft > 0 else { break }
                    let played = voice.totalFrames - voice.framesLeft
                    var envelope: Float = 1
                    if played < attackFrames {
                        envelope = Float(played) / Float(max(1, attackFrames))
                    } else if voice.framesLeft < releaseFrames {
                        envelope = Float(voice.framesLeft) / Float(max(1, releaseFrames))
                    }
                    if let decayFrames = voice.decayFrames {
                        envelope *= Float(exp(-Double(played) / decayFrames))
                    }
                    var wave: Float = 0
                    let base = omega * Double(played)
                    for partial in voice.partials {
                        wave += Float(sin(base * partial.ratio)) * partial.level
                    }
                    let sample = wave * voice.amplitude * envelope
                    voice.framesLeft -= 1
                    for buffer in buffers {
                        guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                        data[frame] += sample
                    }
                }
                voices[index] = voice
            }
            voices.removeAll { $0.framesLeft <= 0 && $0.delayFrames <= 0 }
        }
    }
}

/// The tones for one beep style.
struct ToneSet {
    var countdown: [ToneSynth.Tone]
    var go: [ToneSynth.Tone]
    var restStart: [ToneSynth.Tone]
    var tick: [ToneSynth.Tone]
    var finished: [ToneSynth.Tone]

    static func make(_ style: BeepStyle) -> ToneSet {
        switch style {
        case .classic:
            return ToneSet(countdown: [.countdown], go: [.go], restStart: [.restStart], tick: [.tick], finished: ToneSynth.Tone.finished)
        case .soft:
            return soft
        case .bell:
            return bell
        }
    }

    /// Rounder, lower tones with a gentle fade instead of a hard stop.
    private static let soft: ToneSet = {
        let warm = [ToneSynth.Partial(ratio: 1, level: 1), ToneSynth.Partial(ratio: 2, level: 0.18), ToneSynth.Partial(ratio: 3, level: 0.05)]
        func tone(_ f: Double, _ d: Double, _ a: Float, delay: Double = 0, decay: Double) -> ToneSynth.Tone {
            ToneSynth.Tone(frequency: f, duration: d, amplitude: a, delay: delay, partials: warm, decay: decay)
        }
        return ToneSet(
            countdown: [tone(587, 0.22, 0.5, decay: 0.08)],
            go: [tone(784, 0.8, 0.55, decay: 0.28)],
            restStart: [tone(523, 0.8, 0.5, decay: 0.28)],
            tick: [ToneSynth.Tone(frequency: 1600, duration: 0.02, amplitude: 0.12, decay: 0.006)],
            finished: [
                tone(523, 0.6, 0.5, decay: 0.2),
                tone(659, 0.6, 0.5, delay: 0.2, decay: 0.2),
                tone(784, 1.2, 0.55, delay: 0.4, decay: 0.4)
            ]
        )
    }()

    /// A boxing-ring bell: inharmonic overtones and a long ring.
    private static let bell: ToneSet = {
        let metal = [
            ToneSynth.Partial(ratio: 1, level: 1),
            ToneSynth.Partial(ratio: 2.76, level: 0.55),
            ToneSynth.Partial(ratio: 5.40, level: 0.3),
            ToneSynth.Partial(ratio: 8.93, level: 0.12)
        ]
        func ding(delay: Double = 0, ring: Double = 1.6) -> ToneSynth.Tone {
            ToneSynth.Tone(frequency: 740, duration: ring, amplitude: 0.7, delay: delay, partials: metal, decay: ring / 3.5)
        }
        // Countdown: a short wooden clack, like the timekeeper's sticks.
        let clack = ToneSynth.Tone(frequency: 1150, duration: 0.09, amplitude: 0.55,
                                   partials: [ToneSynth.Partial(ratio: 1, level: 1), ToneSynth.Partial(ratio: 2.3, level: 0.4)],
                                   decay: 0.02)
        return ToneSet(
            countdown: [clack],
            go: [ding()],
            restStart: [ding(ring: 0.9), ding(delay: 0.35)],
            tick: [ToneSynth.Tone(frequency: 1800, duration: 0.02, amplitude: 0.14, decay: 0.005)],
            finished: [ding(ring: 0.9), ding(delay: 0.3, ring: 0.9), ding(delay: 0.6, ring: 2.2)]
        )
    }()
}

extension ToneSynth.Tone {
    static let countdown = ToneSynth.Tone(frequency: 880, duration: 0.12, amplitude: 0.5)
    static let go = ToneSynth.Tone(frequency: 1320, duration: 0.45, amplitude: 0.55)
    static let restStart = ToneSynth.Tone(frequency: 660, duration: 0.45, amplitude: 0.5)
    static let tick = ToneSynth.Tone(frequency: 2400, duration: 0.012, amplitude: 0.18)

    static var finished: [ToneSynth.Tone] {
        [
            ToneSynth.Tone(frequency: 1046, duration: 0.18, amplitude: 0.5),
            ToneSynth.Tone(frequency: 1318, duration: 0.18, amplitude: 0.5, delay: 0.22),
            ToneSynth.Tone(frequency: 1568, duration: 0.5, amplitude: 0.55, delay: 0.44)
        ]
    }
}
