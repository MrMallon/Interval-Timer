import SwiftData
import SwiftUI

/// Create or edit a timer on the watch. Simple, AMRAP and For Time timers are
/// fully editable here; custom (per-interval) timers keep their intervals and can be renamed.
struct WatchEditorView: View {
    enum Layout: Hashable { case simple, amrap, forTime }

    let target: WatchEditorTarget

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String
    @State private var color: ThemeColor
    @State private var layout: Layout
    @State private var config: SimpleConfig
    @State private var amrap: AmrapConfig
    @State private var forTime: ForTimeConfig
    private let customDefinition: TimerDefinition?

    init(target: WatchEditorTarget) {
        self.target = target
        var layout = Layout.simple
        var config = SimpleConfig()
        var amrap = AmrapConfig()
        var forTime = ForTimeConfig()
        var custom: TimerDefinition?
        switch target {
        case .new:
            _name = State(initialValue: String(localized: "My timer"))
            _color = State(initialValue: .red)
        case .existing(let template):
            _name = State(initialValue: template.name)
            _color = State(initialValue: template.color)
            switch template.definition {
            case .simple(let value): config = value
            case .amrap(let value): layout = .amrap; amrap = value
            case .forTime(let value): layout = .forTime; forTime = value
            case .custom: custom = template.definition
            }
        }
        _layout = State(initialValue: layout)
        _config = State(initialValue: config)
        _amrap = State(initialValue: amrap)
        _forTime = State(initialValue: forTime)
        customDefinition = custom
    }

    private var definition: TimerDefinition {
        if let customDefinition { return customDefinition }
        switch layout {
        case .simple: return .simple(config)
        case .amrap: return .amrap(amrap)
        case .forTime: return .forTime(forTime)
        }
    }

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
                    if customDefinition == nil {
                        Picker("Layout", selection: $layout) {
                            Text("Simple").tag(Layout.simple)
                            Text(verbatim: "AMRAP").tag(Layout.amrap)
                            Text("For Time", comment: "Workout type: finish the work as fast as possible").tag(Layout.forTime)
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
                    switch layout {
                    case .simple: simpleSections
                    case .amrap: amrapSections
                    case .forTime: forTimeSections
                    }
                }

                Section {
                    LabeledContent("Total", value: TimerSummary.totalText(WorkoutPlan(name: name, definition: definition)))
                        .monospacedDigit()
                    Button("Save", action: save)
                        .foregroundStyle(color.color)
                }
            }
            .navigationTitle(isNew ? "New timer" : "Edit")
        }
    }

    @ViewBuilder
    private var simpleSections: some View {
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

    @ViewBuilder
    private var amrapSections: some View {
        Section {
            SecondsStepper(title: "Get ready", seconds: $amrap.prepare, range: 0...600)
            // Whole minutes are what AMRAPs are written in; 15-second steps still allow 7:30.
            SecondsStepper(title: "AMRAP length", seconds: $amrap.work, range: 15...3600, step: 15)
            Stepper(value: $amrap.sets, in: 1...10) {
                LabeledContent("Sets", value: "\(amrap.sets)")
            }
            if amrap.sets > 1 {
                SecondsStepper(title: "Rest between sets", seconds: $amrap.rest, range: 0...1800)
            }
            SecondsStepper(title: "Cool down", seconds: $amrap.coolDown, range: 0...1800)
        }
    }

    @ViewBuilder
    private var forTimeSections: some View {
        Section {
            SecondsStepper(title: "Get ready", seconds: $forTime.prepare, range: 0...600)
            SecondsStepper(title: "Time cap", seconds: $forTime.timeCap, range: 0...7200, step: 60, zeroText: "None")
        } footer: {
            Text("Tap Done when you finish")
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

/// A Digital Crown friendly duration stepper, in 5-second steps unless told otherwise.
private struct SecondsStepper: View {
    let title: LocalizedStringKey
    @Binding var seconds: Int
    let range: ClosedRange<Int>
    var step = 5
    /// Shown instead of 0:00, e.g. "None" for no time cap.
    var zeroText: LocalizedStringKey?

    var body: some View {
        Stepper(value: $seconds, in: range, step: step) {
            LabeledContent {
                if seconds == 0, let zeroText {
                    Text(zeroText)
                } else {
                    Text(TimeFormat.clock(seconds))
                }
            } label: {
                Text(title)
            }
            .monospacedDigit()
        }
    }
}
