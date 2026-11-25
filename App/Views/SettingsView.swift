import AVFoundation
import SwiftUI
import TimerKit

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var soundPreview = SoundPreview()
    @State private var healthDenied = HealthLogger.isDenied

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    Toggle("Beeps", isOn: $settings.cue.beeps)
                    Picker("Beep sound", selection: $settings.cue.beepStyle) {
                        ForEach(BeepStyle.allCases, id: \.self) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .disabled(!settings.cue.beeps)
                    .onChange(of: settings.cue.beepStyle) { _, style in
                        soundPreview.play(style)
                    }
                    Toggle("Voice guidance", isOn: $settings.cue.voice)
                    Toggle("Ticking every second", isOn: $settings.cue.ticking)
                    Stepper(value: $settings.cue.countdownSeconds, in: 0...10) {
                        LabeledContent(
                            "Final countdown",
                            value: settings.cue.countdownSeconds == 0
                                ? String(localized: "Off")
                                : String(localized: "\(settings.cue.countdownSeconds) s")
                        )
                    }
                } header: {
                    Text("Sounds")
                } footer: {
                    Text("Cues play over your music. With every sound off, the app never touches your audio.")
                }

                Section {
                    NavigationLink {
                        VoicePickerView()
                    } label: {
                        LabeledContent("Speaking voice", value: voiceName)
                    }
                    Toggle("Time left announcements", isOn: $settings.cue.timeMarkers)
                    Toggle("Announce what's next during rest", isOn: $settings.cue.announceNext)
                    Toggle("Lower music while speaking", isOn: $settings.cue.duckMusic)
                } header: {
                    Text("Voice")
                } footer: {
                    Text("Time left is spoken at 5 min, 1 min and 30 s in long intervals.")
                }
                .disabled(!settings.cue.voice)

                if HealthLogger.isAvailable {
                    Section {
                        Toggle("Save workouts to Apple Health", isOn: $settings.saveToHealth)
                            .onChange(of: settings.saveToHealth) { _, on in
                                guard on else { return }
                                Task {
                                    let allowed = await HealthLogger.requestAccess()
                                    healthDenied = !allowed
                                    if !allowed { settings.saveToHealth = false }
                                }
                            }
                    } header: {
                        Text("Apple Health")
                    } footer: {
                        if healthDenied {
                            Text("Health access is off. You can allow it in the Health app.")
                        } else {
                            Text("Adds each finished workout of 30 s or longer to Health. Interval Timer never reads your health data.")
                        }
                    }
                }

                Section("Screen") {
                    Toggle("Flash on phase change", isOn: $settings.cue.flash)
                    Toggle("Pale colours", isOn: $settings.paleColors)
                    Toggle("Keep screen on during workouts", isOn: $settings.keepScreenAwake)
                    Toggle("Vibrate", isOn: $settings.cue.haptics)
                }

                Section {
                    LabeledContent("Version", value: Bundle.main.appVersion)
                } header: {
                    Text("About")
                } footer: {
                    Text("Free forever. No ads, no subscriptions, no tracking. Your workouts stay on your device.")
                }
            }
            .navigationTitle("Settings")
        }
    }

    /// The picked voice's name, or "Automatic" when none is picked or it was deleted.
    private var voiceName: String {
        guard let id = settings.cue.voiceIdentifier,
              let voice = AVSpeechSynthesisVoice(identifier: id) else {
            return String(localized: "Automatic")
        }
        return voice.name
    }
}

extension BeepStyle {
    var title: LocalizedStringKey {
        switch self {
        case .classic: return "Classic"
        case .soft: return "Soft"
        case .bell: return "Boxing bell"
        }
    }
}

/// Plays a style's "work starts" sound once, so people can hear what they picked.
@MainActor
final class SoundPreview {
    private let player = AudioCuePlayer()
    private var release: Task<Void, Never>?

    func play(_ style: BeepStyle) {
        release?.cancel()
        player.activate(settings: CueSettings(beeps: true, voice: false, ticking: false))
        let tones = ToneSet.make(style)
        player.play(tones: tones.countdown + tones.go.map { tone in
            var later = tone
            later.delay += 0.5
            return later
        })
        release = Task { [player] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            player.deactivate()
        }
    }
}

private extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
