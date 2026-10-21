import SwiftData
import SwiftUI

/// Create or edit a timer on the watch. Simple timers are fully editable here;
/// custom (per-interval) timers keep their intervals and can be renamed.
struct WatchEditorView: View {
    let target: WatchEditorTarget

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String
    @State private var color: ThemeColor
    @State private var config: SimpleConfig
    private let customDefinition: TimerDefinition?

    init(target: WatchEditorTarget) {
        self.target = target
        switch target {
        case .new:
            _name = State(initialValue: String(localized: "My timer"))
            _color = State(initialValue: .red)
            _config = State(initialValue: SimpleConfig())
            customDefinition = nil
        case .existing(let template):
            _name = State(initialValue: template.name)
            _color = State(initialValue: template.color)
            if case .simple(let simple) = template.definition {
                _config = State(initialValue: simple)
                customDefinition = nil
            } else {
                _config = State(initialValue: SimpleConfig())
                customDefinition = template.definition
            }
        }
    }

    private var definition: TimerDefinition { customDefinition ?? .simple(config) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    Picker("Colour", selection: $color) {
                        ForEach(ThemeColor.allCases) { theme in
                            HStack {
                                Circle().fill(theme.color).frame(width: 12, height: 12)
                                Text(theme.accessibilityName)
                            }
                            .tag(theme)
                        }
                    }
                }

                if customDefinition != nil {
                    Section {
                        Text("This timer has custom intervals. Change them on your iPhone.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Intervals") {
                        SecondsStepper(title: "Get ready", seconds: $config.prepare, range: 0...600)
                        SecondsStepper(title: "Work", seconds: $config.work, range: 5...3600)
                        SecondsStepper(title: "Rest", seconds: $config.rest, range: 0...3600)
                        Stepper(value: $config.rounds, in: 1...99) {
                            LabeledContent("Rounds", value: "\(config.rounds)")
                        }
                    }
                    Section("Cycles") {
                        Stepper(value: $config.cycles, in: 1...20) {
                            LabeledContent("Cycles", value: "\(config.cycles)")
                        }
                        if config.cycles > 1 {
                            SecondsStepper(title: "Between cycles", seconds: $config.restBetweenCycles, range: 0...3600)
                        }
                        SecondsStepper(title: "Cool down", seconds: $config.coolDown, range: 0...1800)
                    }
                }

                Section {
                    LabeledContent("Total", value: TimeFormat.clock(WorkoutPlan(name: name, definition: definition).totalDuration))
                        .monospacedDigit()
                    Button("Save", action: save)
                        .foregroundStyle(color.color)
                }
            }
            .navigationTitle(isNew ? "New timer" : "Edit")
        }
    }

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let finalName = trimmed.isEmpty ? String(localized: "My timer") : trimmed
        switch target {
        case .existing(let template):
            template.name = finalName
            template.color = color
            template.definition = definition   // also bumps updatedAt for sync
        case .new:
            let maxOrder = (try? modelContext.fetch(FetchDescriptor<TimerTemplate>()))?.map(\.sortOrder).max() ?? -1
            modelContext.insert(TimerTemplate(name: finalName, definition: definition, color: color, sortOrder: maxOrder + 1))
        }
        try? modelContext.save()
        SyncCoordinator.shared.libraryChanged()
        dismiss()
    }
}

/// A Digital Crown friendly duration stepper in 5-second steps.
private struct SecondsStepper: View {
    let title: LocalizedStringKey
    @Binding var seconds: Int
    let range: ClosedRange<Int>

    var body: some View {
        Stepper(value: $seconds, in: range, step: 5) {
            LabeledContent(title, value: TimeFormat.clock(seconds))
                .monospacedDigit()
        }
    }
}
