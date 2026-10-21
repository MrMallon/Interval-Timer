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
    }

    private struct Voice {
        var frequency: Double
        var amplitude: Float
        var totalFrames: Int
        var framesLeft: Int
        var delayFrames: Int
        var phase: Double = 0
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
                delayFrames: Int(tone.delay * rate)
            )
        }
        state.withLockUnchecked { $0.append(contentsOf: voices) }
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
                let increment = 2 * Double.pi * voice.frequency / rate
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
                    let sample = Float(sin(voice.phase)) * voice.amplitude * envelope
                    voice.phase += increment
                    if voice.phase > 2 * Double.pi { voice.phase -= 2 * Double.pi }
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
