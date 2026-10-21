import SwiftData
import SwiftUI

struct WatchSettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Cues") {
                Toggle("Sounds and taps", isOn: $settings.cue.beeps)
                Toggle("Voice", isOn: $settings.cue.voice)
                Toggle("Tap every second", isOn: $settings.cue.ticking)
                Stepper(value: $settings.cue.countdownSeconds, in: 0...10) {
                    LabeledContent("Countdown", value: settings.cue.countdownSeconds == 0
                                   ? String(localized: "Off")
                                   : String(localized: "\(settings.cue.countdownSeconds) s"))
                }
            }
            Section("Voice") {
                Toggle("Time left", isOn: $settings.cue.timeMarkers)
                Toggle("What's next", isOn: $settings.cue.announceNext)
            }
            .disabled(!settings.cue.voice)
            Section("Screen") {
                Toggle("Flash", isOn: $settings.cue.flash)
                Toggle("Pale colours", isOn: $settings.paleColors)
            }
            Section {
                Text("Free forever. No ads, no tracking.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}

struct WatchHistoryView: View {
    @Query(sort: \WorkoutRecord.startedAt, order: .reverse) private var records: [WorkoutRecord]

    var body: some View {
        List {
            if records.isEmpty {
                Text("Finished workouts from your watch and iPhone show up here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(records.prefix(50)) { record in
                VStack(alignment: .leading, spacing: 2) {
                    Text(record.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(record.startedAt.formatted(date: .abbreviated, time: .shortened)) · \(TimeFormat.clock(Int(record.totalSeconds.rounded())))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle("History")
    }
}
