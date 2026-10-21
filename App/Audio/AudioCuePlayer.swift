import AVFoundation
import TimerKit

/// Owns the audio session, the tone synth and the speech synthesizer.
///
/// Rules that fix Timer Plus's most-cited audio complaint:
/// - We always *mix* with the user's music (`.mixWithOthers`).
/// - We only duck other audio while a voice line is speaking, and only when
///   the user turned "Lower music while speaking" on.
/// - When every sound is off we never activate the session at all, so the
///   user's volume is never touched.
@MainActor
final class AudioCuePlayer: NSObject {
    /// Called when another app or a phone call interrupts us (`true` = began).
    var onInterruption: ((_ began: Bool, _ shouldResume: Bool) -> Void)?

    private let session = AVAudioSession.sharedInstance()
    private let engine = AVAudioEngine()
    private let synth = ToneSynth()
    private let speech = AVSpeechSynthesizer()
    private var sourceNode: AVAudioSourceNode?
    private var isActive = false
    private var duckingEnabled = false
    private var isDucked = false

    override init() {
        super.init()
        speech.delegate = self
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: session
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMediaReset(_:)),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: session
        )
    }

    // MARK: - Lifecycle

    /// Activates audio for a workout. No-op when all sounds are off.
    func activate(settings: CueSettings) {
        duckingEnabled = settings.duckMusic
        guard !settings.isSilent else { return }
        guard !isActive else { return }
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            try startEngine()
            isActive = true
        } catch {
            print("Audio activation failed: \(error)")
        }
    }

    func deactivate() {
        speech.stopSpeaking(at: .immediate)
        synth.stopAll()
        engine.stop()
        if isActive {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }
        isActive = false
        isDucked = false
    }

    private func startEngine() throws {
        if sourceNode == nil {
            let outputFormat = engine.outputNode.inputFormat(forBus: 0)
            let sampleRate = outputFormat.sampleRate > 0 ? outputFormat.sampleRate : 44_100
            synth.configure(sampleRate: sampleRate)
            guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
                throw NSError(domain: "AudioCuePlayer", code: 1)
            }
            let node = Self.makeSourceNode(format: format, synth: synth)
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
            sourceNode = node
        }
        if !engine.isRunning {
            engine.prepare()
            try engine.start()
        }
    }

    /// Built outside the main actor so the real-time render block carries no actor isolation.
    private nonisolated static func makeSourceNode(format: AVAudioFormat, synth: ToneSynth) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            synth.render(
                frameCount: Int(frameCount),
                into: UnsafeMutableAudioBufferListPointer(audioBufferList)
            )
            return noErr
        }
    }

    // MARK: - Playback

    func play(tone: ToneSynth.Tone) {
        guard isActive else { return }
        synth.play([tone])
    }

    func play(tones: [ToneSynth.Tone]) {
        guard isActive else { return }
        synth.play(tones)
    }

    func speak(_ text: String, interrupt: Bool = true) {
        guard isActive else { return }
        if interrupt, speech.isSpeaking {
            speech.stopSpeaking(at: .immediate)
        }
        if duckingEnabled { setDucked(true) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        utterance.volume = 1
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first ?? "en-US")
        speech.speak(utterance)
    }

    private func setDucked(_ ducked: Bool) {
        guard isActive, ducked != isDucked else { return }
        let options: AVAudioSession.CategoryOptions = ducked ? [.mixWithOthers, .duckOthers] : [.mixWithOthers]
        do {
            if !ducked {
                // iOS only lifts ducking when the session deactivates. Pause our
                // (silent at this point) engine so deactivation isn't refused as busy.
                engine.pause()
                try? session.setActive(false, options: .notifyOthersOnDeactivation)
            }
            try session.setCategory(.playback, mode: .default, options: options)
            try session.setActive(true)
            if !engine.isRunning { try engine.start() }
            isDucked = ducked
        } catch {
            print("Ducking change failed: \(error)")
        }
    }

    // MARK: - Notifications

    @objc private nonisolated func handleInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }
        let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
        let shouldResume = AVAudioSession.InterruptionOptions(rawValue: optionsValue).contains(.shouldResume)
        let began = type == .began
        Task { @MainActor [weak self] in
            self?.processInterruption(began: began, shouldResume: shouldResume)
        }
    }

    private func processInterruption(began: Bool, shouldResume: Bool) {
        if began {
            onInterruption?(true, false)
            return
        }
        if isActive {
            try? session.setActive(true)
            if !engine.isRunning { try? engine.start() }
        }
        onInterruption?(false, shouldResume)
    }

    @objc private nonisolated func handleMediaReset(_ notification: Notification) {
        Task { @MainActor [weak self] in
            self?.rebuildAfterReset()
        }
    }

    private func rebuildAfterReset() {
        // Audio services restarted: rebuild the graph.
        let wasActive = isActive
        isActive = false
        if let sourceNode {
            engine.detach(sourceNode)
        }
        sourceNode = nil
        if wasActive {
            activate(settings: CueSettings(duckMusic: duckingEnabled))
        }
    }
}

extension AudioCuePlayer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, !self.speech.isSpeaking else { return }
            self.setDucked(false)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, !self.speech.isSpeaking else { return }
            self.setDucked(false)
        }
    }
}
