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
///
/// Activating and deactivating the audio session can block for a noticeable
/// time, so that work runs in order on `AudioSessionWorker`'s background
/// queue and never on the main thread.
@MainActor
final class AudioCuePlayer: NSObject {
    /// Called when another app or a phone call interrupts us (`true` = began).
    var onInterruption: ((_ began: Bool, _ shouldResume: Bool) -> Void)?

    private let worker = AudioSessionWorker()
    private let speech = AVSpeechSynthesizer()
    /// True from `activate` until `deactivate` (the session itself follows a moment later).
    private var isActive = false
    private var duckingEnabled = false
    private var settings = CueSettings()
    private var voice: AVSpeechSynthesisVoice?
    private var isDucked = false
    /// Lines waiting for the music to finish lowering before they're spoken.
    private var waitingToSpeak: [AVSpeechUtterance] = []
    private var duckPending = false
    /// Lifts the ducking once speech has really gone quiet. Speech callbacks alone
    /// aren't enough: `isSpeaking` can still read true when `didFinish` arrives,
    /// which used to leave the user's music lowered until the next voice line.
    private var undockWatch: Task<Void, Never>?
    private var undockRetries = 0

    override init() {
        super.init()
        speech.delegate = self
        let session = AVAudioSession.sharedInstance()
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
        self.settings = settings
        duckingEnabled = settings.duckMusic
        // Looked up once per workout: listing installed voices is too slow for every cue.
        voice = settings.voice ? SpeechVoices.voice(identifier: settings.voiceIdentifier) : nil
        guard !settings.isSilent else { return }
        guard !isActive else { return }
        isActive = true
        worker.activate()
    }

    /// True while audio is switched on for a workout (never when every sound is off).
    var isSessionActive: Bool { isActive }

    /// True while the tone engine renders; this is what keeps the app alive on a locked screen.
    var isEngineRunning: Bool { worker.isEngineRunning }

    func deactivate() {
        speech.stopSpeaking(at: .immediate)
        waitingToSpeak.removeAll()
        worker.synth.stopAll()
        if isActive { worker.deactivate() }
        isActive = false
        isDucked = false
        duckPending = false
        undockWatch?.cancel()
        undockWatch = nil
    }

    /// Waits until queued audio session changes have been applied. For tests.
    func settle() async {
        await worker.settle()
    }

    // MARK: - Playback

    func play(tone: ToneSynth.Tone) {
        play(tones: [tone])
    }

    func play(tones: [ToneSynth.Tone]) {
        guard isActive else { return }
        worker.synth.play(tones)
    }

    func speak(_ text: String, interrupt: Bool = true) {
        guard isActive else { return }
        if interrupt {
            waitingToSpeak.removeAll()
            if speech.isSpeaking { speech.stopSpeaking(at: .immediate) }
        }
        let utterance = AVSpeechUtterance(string: text)
        // Natural pace: anything faster makes the voice sound clipped and harsh.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = 1
        utterance.voice = voice ?? SpeechVoices.voice(identifier: settings.voiceIdentifier)
        if duckingEnabled, !isDucked || duckPending {
            // Lower the music first: changing the audio session mid-sentence cuts the voice off.
            waitingToSpeak.append(utterance)
            setDucked(true)
        } else {
            speech.speak(utterance)
        }
    }

    private func setDucked(_ ducked: Bool) {
        guard isActive, ducked != isDucked else { return }
        isDucked = ducked
        duckPending = ducked
        if ducked {
            undockRetries = 0
            startUndockWatch()
        } else {
            undockWatch?.cancel()
            undockWatch = nil
        }
        worker.setDucked(ducked) { [weak self] succeeded in
            Task { @MainActor in self?.duckApplied(ducked, succeeded: succeeded) }
        }
    }

    private func duckApplied(_ ducked: Bool, succeeded: Bool) {
        if !ducked {
            // iOS refused to lift the ducking: try again shortly so the music
            // doesn't stay quiet for the rest of the workout.
            guard !succeeded, isActive, !isDucked, undockRetries < 5 else { return }
            undockRetries += 1
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self, self.isActive, !self.isDucked else { return }
                self.worker.setDucked(false) { [weak self] succeeded in
                    Task { @MainActor in self?.duckApplied(false, succeeded: succeeded) }
                }
            }
            return
        }
        guard isDucked, duckPending else { return }
        duckPending = false
        let lines = waitingToSpeak
        waitingToSpeak.removeAll()
        lines.forEach { speech.speak($0) }
    }

    /// Nothing is speaking or about to speak.
    private var isQuiet: Bool {
        !speech.isSpeaking && waitingToSpeak.isEmpty && !duckPending
    }

    /// While ducked, checks a few times a second and restores the music once
    /// speech has been quiet for two checks in a row (so back-to-back lines
    /// don't make the music bounce up and down).
    private func startUndockWatch() {
        undockWatch?.cancel()
        undockWatch = Task { @MainActor [weak self] in
            var quietChecks = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 200_000_000)
                guard !Task.isCancelled, let self, self.isDucked else { return }
                quietChecks = self.isQuiet ? quietChecks + 1 : 0
                if quietChecks >= 2 {
                    self.setDucked(false)
                    return
                }
            }
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
        if isActive { worker.resumeAfterInterruption(ducked: isDucked && !duckPending) }
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
        isDucked = false
        duckPending = false
        undockWatch?.cancel()
        undockWatch = nil
        worker.discardGraph()
        if wasActive {
            activate(settings: settings)
        }
    }
}

extension AudioCuePlayer: AVSpeechSynthesizerDelegate {
    // Music is restored by `startUndockWatch`, not here: at these callbacks the
    // synthesizer can still report it is speaking and still be holding audio,
    // so un-ducking from them was skipped or refused now and then.
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {}

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {}
}

/// Does the slow audio session and engine work on its own serial queue, in the
/// order it was asked for. Everything it touches is only used on that queue
/// (the synth has its own lock), which is what makes the `@unchecked Sendable` safe.
final class AudioSessionWorker: @unchecked Sendable {
    let synth = ToneSynth()
    /// One queue for every player: they all share the app's single audio session,
    /// so one player's shutdown must finish before the next one starts up.
    private static let sharedQueue = DispatchQueue(label: "com.mrmallon.intervaltimer.audio", qos: .userInitiated)
    private var queue: DispatchQueue { Self.sharedQueue }
    private let session = AVAudioSession.sharedInstance()
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?

    var isEngineRunning: Bool { engine.isRunning }

    func activate() {
        queue.async { [self] in
            do {
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)
            } catch {
                print("Audio session activation failed: \(error)")
                return
            }
            do {
                try startEngine()
            } catch {
                print("Audio engine failed to start: \(error)")
            }
        }
    }

    func deactivate() {
        queue.async { [self] in
            engine.stop()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    /// `done` runs on the audio queue once the change has been applied, with
    /// `false` if iOS refused it.
    func setDucked(_ ducked: Bool, done: @escaping @Sendable (_ succeeded: Bool) -> Void = { _ in }) {
        queue.async { [self] in
            var succeeded = true
            let options: AVAudioSession.CategoryOptions = ducked ? [.mixWithOthers, .duckOthers] : [.mixWithOthers]
            if !ducked {
                // iOS only lifts ducking when the session deactivates. Pause our
                // (silent at this point) engine so deactivation isn't refused as busy.
                engine.pause()
                succeeded = deactivateForUnduck()
            }
            do {
                try session.setCategory(.playback, mode: .default, options: options)
                try session.setActive(true)
                if !engine.isRunning { try engine.start() }
            } catch {
                print("Ducking change failed: \(error)")
                succeeded = false
            }
            done(succeeded)
        }
    }

    /// The speech voice can hold on to audio for a moment after it finishes,
    /// and iOS then refuses to deactivate. Try a few times before giving up.
    private func deactivateForUnduck() -> Bool {
        for attempt in 0..<4 {
            do {
                try session.setActive(false, options: .notifyOthersOnDeactivation)
                return true
            } catch {
                if attempt < 3 { Thread.sleep(forTimeInterval: 0.1) }
            }
        }
        print("Could not release ducked audio")
        return false
    }

    /// `ducked` is whether the music should still be lowered after the interruption.
    func resumeAfterInterruption(ducked: Bool) {
        queue.async { [self] in
            let options: AVAudioSession.CategoryOptions = ducked ? [.mixWithOthers, .duckOthers] : [.mixWithOthers]
            try? session.setCategory(.playback, mode: .default, options: options)
            try? session.setActive(true)
            if !engine.isRunning { try? engine.start() }
        }
    }

    /// After an audio services reset the old graph is dead; the next `activate` builds a new one.
    func discardGraph() {
        queue.async { [self] in
            if let sourceNode {
                engine.detach(sourceNode)
            }
            sourceNode = nil
        }
    }

    func settle() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
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

    private static func makeSourceNode(format: AVAudioFormat, synth: ToneSynth) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
            synth.render(
                frameCount: Int(frameCount),
                into: UnsafeMutableAudioBufferListPointer(audioBufferList)
            )
            return noErr
        }
    }
}
