import SwiftUI
import TimerKit

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            Form {
                Section {
                    Toggle("Beeps", isOn: $settings.cue.beeps)
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
                    Toggle("Time left announcements", isOn: $settings.cue.timeMarkers)
                    Toggle("Announce what's next during rest", isOn: $settings.cue.announceNext)
                    Toggle("Lower music while speaking", isOn: $settings.cue.duckMusic)
                } header: {
                    Text("Voice")
                } footer: {
                    Text("Time left is spoken at 5 min, 1 min and 30 s in long intervals.")
                }
                .disabled(!settings.cue.voice)

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
}

private extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
