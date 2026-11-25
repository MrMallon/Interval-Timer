import SwiftData
import SwiftUI
import TimerKit

/// Creates or edits a saved timer. Saving an existing timer updates it in place.
struct TimerEditorView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case simple, custom, amrap, forTime
        var id: String { rawValue }
        var title: Text {
            switch self {
            case .simple: return Text("Simple")
            case .custom: return Text("Custom")
            // The same in every language.
            case .amrap: return Text(verbatim: "AMRAP")
            case .forTime: return Text("For Time", comment: "Workout type: finish the work as fast as possible")
            }
        }
    }

    let target: EditorTarget

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var name: String
    @State private var color: ThemeColor
    @State private var mode: Mode
    @State private var config: SimpleConfig
    @State private var segments: [Segment]
    @State private var amrap: AmrapConfig
    @State private var forTime: ForTimeConfig
    /// Leaving Custom replaces the intervals, so it asks first.
    @State private var pendingMode: Mode?

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
        var mode = Mode.simple
        var config = SimpleConfig()
        var amrap = AmrapConfig()
        var forTime = ForTimeConfig()
        var segments: [Segment] = []
        switch definition {
        case .simple(let simple):
            config = simple
        case .custom(let custom):
            mode = .custom
            segments = custom
        case .amrap(let value):
            mode = .amrap
            amrap = value
        case .forTime(let value):
            mode = .forTime
            forTime = value
        }
        _mode = State(initialValue: mode)
        _config = State(initialValue: config)
        _amrap = State(initialValue: amrap)
        _forTime = State(initialValue: forTime)
        _segments = State(initialValue: segments)
    }

    private var isNew: Bool {
        if case .new = target { return true }
        return false
    }

    private var definition: TimerDefinition {
        switch mode {
        case .simple: return .simple(config)
        case .custom: return .custom(Self.renumbered(segments))
        case .amrap: return .amrap(amrap)
        case .forTime: return .forTime(forTime)
        }
    }

    /// The selected layout's segments before any editing in Custom.
    private func segments(for mode: Mode) -> [Segment] {
        switch mode {
        case .simple: return config.segments()
        case .custom: return segments
        case .amrap: return amrap.segments()
        case .forTime: return forTime.segments()
        }
    }

    private var plan: WorkoutPlan { WorkoutPlan(name: name, definition: definition) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                        .font(.headline)
                        .accessibilityIdentifier("nameField")
                    ColorRow(selection: $color)
                }

                Section {
                    Picker("Layout", selection: modeBinding) {
                        ForEach(Mode.allCases) { mode in
                            mode.title.tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("layoutPicker")
                } footer: {
                    modeFooter
                }

                switch mode {
                case .simple: simpleSections
                case .custom: customSections
                case .amrap: amrapSections
                case .forTime: forTimeSections
                }

                Section {
                    LabeledContent("Total time", value: TimerSummary.totalText(plan))
                    if mode != .forTime {
                        LabeledContent("Work intervals", value: "\(plan.workCount)")
                        LabeledContent("Time working", value: TimeFormat.clock(plan.totalWork))
                    }
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
                        .accessibilityIdentifier("saveButton")
                }
            }
            .alert(Text("Leave Custom?"), isPresented: leaveCustomBinding) {
                Button("Switch", role: .destructive) {
                    if let pendingMode { mode = pendingMode }
                    pendingMode = nil
                }
                Button("Cancel", role: .cancel) { pendingMode = nil }
            } message: {
                Text("Your custom intervals will be replaced.")
            }
        }
    }

    @ViewBuilder
    private var modeFooter: some View {
        switch mode {
        case .simple:
            Text("Same work and rest every round.")
        case .custom:
            Text("Set each interval yourself: pyramids, ladders, named exercises, repeat groups.")
        case .amrap:
            Text("As many rounds as possible: tap +1 round each time you finish one.")
        case .forTime:
            Text("Finish the work as fast as you can, then tap Done. The clock counts up.")
        }
    }

    private var leaveCustomBinding: Binding<Bool> {
        Binding(get: { pendingMode != nil }, set: { if !$0 { pendingMode = nil } })
    }

    /// Switching to Custom copies the current layout's intervals so nothing is lost.
    private var modeBinding: Binding<Mode> {
        Binding(
            get: { mode },
            set: { newMode in
                guard newMode != mode else { return }
                if newMode == .custom {
                    segments = segments(for: mode)
                    mode = .custom
                } else if mode == .custom {
                    pendingMode = newMode
                } else {
                    mode = newMode
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

    // MARK: - AMRAP and For Time

    @ViewBuilder
    private var amrapSections: some View {
        Section {
            DurationRow(title: "Get ready", seconds: $amrap.prepare, minimum: 0)
            DurationRow(title: "AMRAP length", seconds: $amrap.work, minimum: 1)
                .accessibilityIdentifier("amrapLength")
        }
        Section {
            Stepper(value: $amrap.sets, in: 1...10) {
                LabeledContent("Sets", value: "\(amrap.sets)")
            }
            if amrap.sets > 1 {
                DurationRow(title: "Rest between sets", seconds: $amrap.rest, minimum: 0)
            }
        } footer: {
            Text("Run several AMRAPs with a rest in between.")
        }
        Section {
            DurationRow(title: "Cool down", seconds: $amrap.coolDown, minimum: 0)
        }
    }

    @ViewBuilder
    private var forTimeSections: some View {
        Section {
            DurationRow(title: "Get ready", seconds: $forTime.prepare, minimum: 0)
        }
        Section {
            DurationRow(title: "Time cap", seconds: $forTime.timeCap, minimum: 0, zeroText: "None")
                .accessibilityIdentifier("timeCap")
        } footer: {
            Text("With a time cap the workout ends by itself if you haven't tapped Done.")
        }
    }

    // MARK: - Custom

    /// Runs of neighbouring segments: each repeat group is one run, and so is
    /// each stretch of intervals between groups.
    private struct Run: Identifiable {
        let range: Range<Int>
        let group: RepeatGroup?
        var id: String { group.map { "g-\($0.id)-\(range.lowerBound)" } ?? "s-\(range.lowerBound)" }
    }

    private var runs: [Run] {
        var result: [Run] = []
        var index = 0
        while index < segments.count {
            let group = segments[index].group
            var end = index + 1
            while end < segments.count, segments[end].group?.id == group?.id { end += 1 }
            result.append(Run(range: index..<end, group: group))
            index = end
        }
        return result
    }

    @ViewBuilder
    private var customSections: some View {
        ForEach(Array(runs.enumerated()), id: \.element.id) { position, run in
            Section {
                ForEach(run.range, id: \.self) { index in
                    SegmentEditorRow(
                        segment: binding(at: index),
                        inGroup: run.group != nil,
                        onDuplicate: { duplicate(at: index) },
                        onLeaveGroup: { leaveGroup(at: index) }
                    )
                }
                .onDelete { offsets in
                    segments.remove(atOffsets: IndexSet(offsets.map { $0 + run.range.lowerBound }))
                }
                .onMove { source, destination in
                    var block = Array(segments[run.range])
                    block.move(fromOffsets: source, toOffset: destination)
                    segments.replaceSubrange(run.range, with: block)
                }
                if let group = run.group {
                    Button("Add interval to group", systemImage: "plus") {
                        segments.insert(Segment(kind: .work, duration: 30, group: group), at: run.range.upperBound)
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 4) {
                    if position == 0 {
                        HStack {
                            Text("Intervals")
                            Spacer()
                            EditButton()
                                .font(.caption)
                        }
                    }
                    if let group = run.group {
                        GroupHeader(
                            repeats: Binding(
                                get: { group.repeats },
                                set: { setRepeats($0, for: group.id) }
                            ),
                            onUngroup: { ungroup(group.id) }
                        )
                    }
                }
            }
        }
        Section {
            Button("Add work", systemImage: "flame") { add(.work, seconds: 30) }
            Button("Add rest", systemImage: "pause.circle") { add(.rest, seconds: 15) }
            Button("Add repeat group", systemImage: "repeat") { addGroup() }
                .accessibilityIdentifier("addGroupButton")
            Button("Repeat all intervals", systemImage: "square.on.square") { repeatAll() }
                .disabled(segments.isEmpty)
        } footer: {
            Text("A repeat group runs its intervals several times in a row, like a circuit.")
        }
    }

    /// Index-based, but safe while a row is being deleted.
    private func binding(at index: Int) -> Binding<Segment> {
        Binding(
            get: { segments.indices.contains(index) ? segments[index] : Segment(kind: .work, duration: 1) },
            set: { if segments.indices.contains(index) { segments[index] = $0 } }
        )
    }

    private func add(_ kind: PhaseKind, seconds: Int) {
        segments.append(Segment(kind: kind, duration: seconds))
    }

    /// A new group of work + rest, ×3, before the cool-down.
    private func addGroup() {
        let group = RepeatGroup(repeats: 3)
        let block = [
            Segment(kind: .work, duration: 40, group: group),
            Segment(kind: .rest, duration: 20, group: group)
        ]
        if let coolIndex = segments.lastIndex(where: { $0.kind == .coolDown }), segments[coolIndex].group == nil {
            segments.insert(contentsOf: block, at: coolIndex)
        } else {
            segments.append(contentsOf: block)
        }
    }

    private func duplicate(at index: Int) {
        var copy = segments[index]
        copy.id = UUID()
        segments.insert(copy, at: index + 1)
    }

    private func setRepeats(_ repeats: Int, for groupID: UUID) {
        for index in segments.indices where segments[index].group?.id == groupID {
            segments[index].group?.repeats = repeats
        }
    }

    private func ungroup(_ groupID: UUID) {
        for index in segments.indices where segments[index].group?.id == groupID {
            segments[index].group = nil
        }
    }

    /// Moves the interval out of its group, to just after the group.
    private func leaveGroup(at index: Int) {
        guard let groupID = segments[index].group?.id else { return }
        var segment = segments.remove(at: index)
        segment.group = nil
        var end = index
        while end < segments.count, segments[end].group?.id == groupID { end += 1 }
        segments.insert(segment, at: end)
    }

    /// Appends a copy of the work/rest block (prepare and cool-down stay at the ends).
    private func repeatAll() {
        let body = segments.filter { $0.kind != .prepare && $0.kind != .coolDown }
        guard !body.isEmpty else { return }
        // Copies keep their settings but get fresh ids, and fresh groups.
        var newGroups: [UUID: RepeatGroup] = [:]
        let copies = body.map { segment -> Segment in
            var copy = segment
            copy.id = UUID()
            if let group = segment.group {
                let fresh = newGroups[group.id] ?? RepeatGroup(repeats: group.repeats)
                newGroups[group.id] = fresh
                copy.group = fresh
            }
            return copy
        }
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
        try? modelContext.save()
        SyncCoordinator.shared.libraryChanged()
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
    let inGroup: Bool
    let onDuplicate: () -> Void
    let onLeaveGroup: () -> Void

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
                // Keeps "Get ready" on one line; the name field gives way instead.
                .fixedSize()
                Spacer()
                TextField("Name (optional)", text: labelBinding)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                Menu {
                    Toggle(isOn: tapBinding) {
                        Label("Until I tap Done", systemImage: "hand.tap")
                    }
                    if segment.kind == .work {
                        Toggle(isOn: $segment.countsRounds) {
                            Label("Count rounds (AMRAP)", systemImage: "plus.circle")
                        }
                    }
                    Divider()
                    Button("Duplicate", systemImage: "plus.square.on.square", action: onDuplicate)
                    if inGroup {
                        Button("Remove from group", systemImage: "arrow.up.right.square", action: onLeaveGroup)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Interval options")
                .accessibilityIdentifier("intervalOptions")
            }
            if segment.untilTapped {
                DurationRow(title: "Time cap", seconds: $segment.duration, minimum: 0, zeroText: "None")
                Text("Runs until you tap Done. The clock counts up.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                DurationRow(title: "Length", seconds: $segment.duration, minimum: 1)
            }
        }
        .padding(.vertical, 2)
    }

    private var labelBinding: Binding<String> {
        Binding(
            get: { segment.label ?? "" },
            set: { segment.label = $0.isEmpty ? nil : $0 }
        )
    }

    /// Turning "tap when done" on starts with no cap; turning it off needs a length again.
    private var tapBinding: Binding<Bool> {
        Binding(
            get: { segment.untilTapped },
            set: { on in
                segment.untilTapped = on
                if on {
                    segment.duration = 0
                } else if segment.duration == 0 {
                    segment.duration = 30
                }
            }
        )
    }
}

/// Header of a repeat group: how many times it runs, and a way to undo the group.
private struct GroupHeader: View {
    @Binding var repeats: Int
    let onUngroup: () -> Void

    var body: some View {
        HStack {
            Label {
                Text("Repeat × \(repeats)", comment: "Header of a group of intervals that repeats, e.g. Repeat × 3")
            } icon: {
                Image(systemName: "repeat")
            }
            Spacer()
            Stepper("Repeats", value: $repeats, in: 1...50)
                .labelsHidden()
                .accessibilityIdentifier("groupRepeats")
            Menu {
                Button("Ungroup", systemImage: "rectangle.stack.badge.minus", action: onUngroup)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Group options")
        }
        .textCase(nil)
    }
}

/// A duration row that expands into minute/second wheels when tapped.
struct DurationRow: View {
    let title: LocalizedStringKey
    @Binding var seconds: Int
    var minimum: Int = 0
    /// Shown instead of 0:00, e.g. "None" for no time cap.
    var zeroText: LocalizedStringKey?

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
                    Group {
                        if seconds == 0, let zeroText {
                            Text(zeroText)
                        } else {
                            Text(TimeFormat.clock(seconds))
                        }
                    }
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
