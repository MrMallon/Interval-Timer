import SwiftData
import SwiftUI
import TimerKit

/// Creates or edits a saved timer. Saving an existing timer updates it in place.
struct TimerEditorView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case simple, custom
        var id: String { rawValue }
        var title: LocalizedStringKey { self == .simple ? "Simple" : "Custom" }
    }

    let target: EditorTarget

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String
    @State private var color: ThemeColor
    @State private var mode: Mode
    @State private var config: SimpleConfig
    @State private var segments: [Segment]
    @State private var confirmSimple = false

    init(target: EditorTarget) {
        self.target = target
        let name: String
        let definition: TimerDefinition
        let color: ThemeColor
        switch target {
        case .new(let newName, let newDefinition, let newColor):
            name = newName
            definition = newDefinition
            color = newColor
        case .existing(let template):
            name = template.name
            definition = template.definition
            color = template.color
        }
        _name = State(initialValue: name)
        _color = State(initialValue: color)
        switch definition {
        case .simple(let simple):
            _mode = State(initialValue: .simple)
            _config = State(initialValue: simple)
            _segments = State(initialValue: simple.segments())
        case .custom(let custom):
            _mode = State(initialValue: .custom)
            _config = State(initialValue: SimpleConfig())
            _segments = State(initialValue: custom)
        }
    }

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }

    private var definition: TimerDefinition {
        switch mode {
        case .simple: return .simple(config)
        case .custom: return .custom(Self.renumbered(segments))
        }
    }

    private var plan: WorkoutPlan { WorkoutPlan(name: name, definition: definition) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .font(.headline)
                    ColorRow(selection: $color)
                }

                Section {
                    Picker("Layout", selection: modeBinding) {
                        ForEach(Mode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(mode == .simple
                         ? "Same work and rest every round."
                         : "Set each interval yourself: pyramids, ladders, named exercises.")
                }

                if mode == .simple {
                    simpleSections
                } else {
                    customSections
                }

                Section {
                    LabeledContent("Total time", value: TimeFormat.clock(plan.totalDuration))
                    LabeledContent("Work intervals", value: "\(plan.workCount)")
                    LabeledContent("Time working", value: TimeFormat.clock(plan.totalWork))
                }
                .monospacedDigit()
            }
            .navigationTitle(isNew ? "New timer" : "Edit timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(plan.isEmpty)
                }
            }
            .alert("Switch to Simple?", isPresented: $confirmSimple) {
                Button("Switch", role: .destructive) { mode = .simple }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your custom intervals will be replaced by the simple layout.")
            }
        }
    }

    /// Switching Simple → Custom copies the expanded layout so nothing is lost.
    private var modeBinding: Binding<Mode> {
        Binding(
            get: { mode },
            set: { newMode in
                guard newMode != mode else { return }
                if newMode == .custom {
                    segments = config.segments()
                    mode = .custom
                } else {
                    confirmSimple = true
                }
            }
        )
    }

    // MARK: - Simple

    @ViewBuilder
    private var simpleSections: some View {
        Section("Intervals") {
            DurationRow(title: "Get ready", seconds: $config.prepare, minimum: 0)
            DurationRow(title: "Work", seconds: $config.work, minimum: 1)
            DurationRow(title: "Rest", seconds: $config.rest, minimum: 0)
            Stepper(value: $config.rounds, in: 1...99) {
                LabeledContent("Rounds", value: "\(config.rounds)")
            }
        }
        Section {
            Stepper(value: $config.cycles, in: 1...20) {
                LabeledContent("Cycles", value: "\(config.cycles)")
            }
            if config.cycles > 1 {
                DurationRow(title: "Rest between cycles", seconds: $config.restBetweenCycles, minimum: 0)
            }
        } header: {
            Text("Cycles")
        } footer: {
            Text("A cycle is one full set of rounds. Repeat it with a longer rest in between.")
        }
        Section {
            DurationRow(title: "Cool down", seconds: $config.coolDown, minimum: 0)
        }
    }

    // MARK: - Custom

    @ViewBuilder
    private var customSections: some View {
        Section {
            ForEach($segments) { $segment in
                SegmentEditorRow(segment: $segment)
            }
            .onDelete { segments.remove(atOffsets: $0) }
            .onMove { segments.move(fromOffsets: $0, toOffset: $1) }
        } header: {
            HStack {
                Text("Intervals")
                Spacer()
                EditButton()
                    .font(.caption)
            }
        }
        Section {
            Button("Add work", systemImage: "flame") { add(.work, seconds: 30) }
            Button("Add rest", systemImage: "pause.circle") { add(.rest, seconds: 15) }
            Button("Repeat all intervals", systemImage: "repeat") { repeatAll() }
                .disabled(segments.isEmpty)
        }
    }

    private func add(_ kind: PhaseKind, seconds: Int) {
        segments.append(Segment(kind: kind, duration: seconds))
    }

    /// Appends a copy of the work/rest block (prepare and cool-down stay at the ends).
    private func repeatAll() {
        let body = segments.filter { $0.kind != .prepare && $0.kind != .coolDown }
        guard !body.isEmpty else { return }
        let copies = body.map { Segment(kind: $0.kind, duration: $0.duration, label: $0.label) }
        if let coolIndex = segments.firstIndex(where: { $0.kind == .coolDown }) {
            segments.insert(contentsOf: copies, at: coolIndex)
        } else {
            segments.append(contentsOf: copies)
        }
    }

    /// Numbers work intervals 1...n so the run screen and voice can say "round 3 of 8".
    static func renumbered(_ segments: [Segment]) -> [Segment] {
        var round = 0
        return segments.map { segment in
            var copy = segment
            if segment.kind == .work { round += 1 }
            switch segment.kind {
            case .work, .rest, .cycleRest:
                copy.round = max(round, 1)
                copy.cycle = 1
            case .prepare, .coolDown:
                copy.round = 0
                copy.cycle = 0
            }
            return copy
        }
    }

    // MARK: - Save

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let finalName = trimmed.isEmpty ? String(localized: "My timer") : trimmed
        switch target {
        case .existing(let template):
            template.name = finalName
            template.color = color
            template.definition = definition
        case .new:
            let maxOrder = (try? modelContext.fetch(FetchDescriptor<TimerTemplate>()))?.map(\.sortOrder).max() ?? -1
            modelContext.insert(TimerTemplate(name: finalName, definition: definition, color: color, sortOrder: maxOrder + 1))
        }
        dismiss()
    }
}

// MARK: - Rows

private struct ColorRow: View {
    @Binding var selection: ThemeColor

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(ThemeColor.allCases) { theme in
                    Button {
                        selection = theme
                    } label: {
                        Circle()
                            .fill(theme.color)
                            .frame(width: 30, height: 30)
                            .overlay {
                                if theme == selection {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(.white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(theme.accessibilityName)
                    .accessibilityAddTraits(theme == selection ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct SegmentEditorRow: View {
    @Binding var segment: Segment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Type", selection: $segment.kind) {
                    ForEach(PhaseKind.allCases, id: \.self) { kind in
                        Label(PhaseStyle.name(for: kind), systemImage: PhaseStyle.symbol(for: kind)).tag(kind)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(PhaseStyle.color(for: segment.kind, pale: false))
                Spacer()
                TextField("Name (optional)", text: labelBinding)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
            }
            DurationRow(title: "Length", seconds: $segment.duration, minimum: 1)
        }
        .padding(.vertical, 2)
    }

    private var labelBinding: Binding<String> {
        Binding(
            get: { segment.label ?? "" },
            set: { segment.label = $0.isEmpty ? nil : $0 }
        )
    }
}

/// A duration row that expands into minute/second wheels when tapped.
struct DurationRow: View {
    let title: LocalizedStringKey
    @Binding var seconds: Int
    var minimum: Int = 0

    @State private var expanded = false

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                HStack {
                    Text(title)
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(TimeFormat.clock(seconds))
                        .monospacedDigit()
                        .foregroundStyle(expanded ? Color.accentColor : .secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                HStack(spacing: 0) {
                    Picker("Minutes", selection: minutesBinding) {
                        ForEach(0..<100, id: \.self) { Text("\($0) min").tag($0) }
                    }
                    .pickerStyle(.wheel)
                    Picker("Seconds", selection: secondsBinding) {
                        ForEach(0..<60, id: \.self) { Text("\($0) s").tag($0) }
                    }
                    .pickerStyle(.wheel)
                }
                .frame(height: 140)
            }
        }
        .accessibilityElement(children: expanded ? .contain : .combine)
        .accessibilityValue(TimeFormat.clock(seconds))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: seconds += 5
            case .decrement: seconds = max(minimum, seconds - 5)
            @unknown default: break
            }
        }
    }

    private var minutesBinding: Binding<Int> {
        Binding(
            get: { seconds / 60 },
            set: { seconds = max(minimum, $0 * 60 + seconds % 60) }
        )
    }

    private var secondsBinding: Binding<Int> {
        Binding(
            get: { seconds % 60 },
            set: { seconds = max(minimum, (seconds / 60) * 60 + $0) }
        )
    }
}
