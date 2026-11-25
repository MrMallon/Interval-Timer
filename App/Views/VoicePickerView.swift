import AVFoundation
import SwiftUI

/// Pick the voice that speaks cues. Tapping a voice selects it and plays a sample.
struct VoicePickerView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var voices: [AVSpeechSynthesisVoice] = []
    @State private var previewer = VoicePreviewer()

    /// The saved voice, or nil (Automatic) when none is saved or it has since been deleted.
    private var selectedID: String? {
        guard let id = settings.cue.voiceIdentifier,
              voices.contains(where: { $0.identifier == id }) else { return nil }
        return id
    }

    var body: some View {
        List {
            Section {
                row(
                    title: String(localized: "Automatic"),
                    detail: String(localized: "Best voice installed"),
                    identifier: nil
                )
            } header: {
                Text("Tap a voice to hear it.")
            }

            Section {
                ForEach(voices, id: \.identifier) { voice in
                    row(title: voice.name, detail: Self.detail(for: voice), identifier: voice.identifier)
                }
            } footer: {
                Text("For a more natural voice, download an Enhanced or Premium voice in Settings › Accessibility › Spoken Content › Voices.")
            }
        }
        .navigationTitle("Speaking voice")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { voices = SpeechVoices.available() }
        .onDisappear { previewer.stop() }
    }

    private func row(title: String, detail: String, identifier: String?) -> some View {
        let isSelected = selectedID == identifier
        return Button {
            settings.cue.voiceIdentifier = identifier
            previewer.play(voice: SpeechVoices.voice(identifier: identifier))
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .foregroundStyle(.primary)
                    Text(verbatim: detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// "English (United Kingdom) · Premium"
    static func detail(for voice: AVSpeechSynthesisVoice) -> String {
        let language = Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language
        switch voice.quality {
        case .premium: return "\(language) · \(String(localized: "Premium"))"
        case .enhanced: return "\(language) · \(String(localized: "Enhanced"))"
        default: return language
        }
    }
}

/// Plays a short sample in the chosen voice. Mixes with music, never stops it.
@MainActor
final class VoicePreviewer: NSObject, AVSpeechSynthesizerDelegate {
    private let speech = AVSpeechSynthesizer()

    override init() {
        super.init()
        speech.delegate = self
    }

    func play(voice: AVSpeechSynthesisVoice?) {
        speech.stopSpeaking(at: .immediate)
        // .playback so the sample is heard with the ring/silent switch on.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: String(localized: "Workout complete. Great job!"))
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.voice = voice
        speech.speak(utterance)
    }

    func stop() {
        speech.stopSpeaking(at: .immediate)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.release() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.release() }
    }

    private func release() {
        guard !speech.isSpeaking else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
