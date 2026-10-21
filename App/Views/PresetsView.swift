import SwiftUI
import TimerKit

/// Built-in starting points. Picking one opens the editor on a copy.
struct PresetsView: View {
    let onPick: (Preset) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(Preset.all) { preset in
                Button {
                    onPick(preset)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(PresetText.name(preset))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(PresetText.summary(preset))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(TimeFormat.clock(WorkoutPlan(name: preset.name, definition: preset.definition).totalDuration))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 4)
                }
            }
            .tint(.primary)
            .navigationTitle("Presets")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
