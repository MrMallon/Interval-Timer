import SwiftData
import SwiftUI
import TimerKit

/// What the editor sheet is editing.
enum EditorTarget: Identifiable {
    case new(name: String, definition: TimerDefinition, color: ThemeColor)
    case existing(TimerTemplate)

    var id: String {
        switch self {
        case .new(let name, _, _): return "new-\(name)"
        case .existing(let template): return template.id.uuidString
        }
    }
}

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settings
    @Query(sort: [SortDescriptor(\TimerTemplate.sortOrder), SortDescriptor(\TimerTemplate.createdAt)])
    private var templates: [TimerTemplate]

    @State private var editorTarget: EditorTarget?
    @State private var showingPresets = false
    @State private var pickedPreset: Preset?
    @State private var activeRun: RunSession?

    var body: some View {
        NavigationStack {
            Group {
                if templates.isEmpty {
                    ContentUnavailableView {
                        Label("No timers yet", systemImage: "timer")
                    } description: {
                        Text("Create your own or start from a preset like Tabata or boxing rounds.")
                    } actions: {
                        Button("New timer") { newTimer() }
                            .buttonStyle(.borderedProminent)
                        Button("Browse presets") { showingPresets = true }
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Timers")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("New timer", systemImage: "plus") { newTimer() }
                        Button("From a preset", systemImage: "square.grid.2x2") { showingPresets = true }
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel("Add timer")
                    }
                }
                if !templates.isEmpty {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                }
            }
            .sheet(item: $editorTarget) { target in
                TimerEditorView(target: target)
            }
            .sheet(isPresented: $showingPresets, onDismiss: openPickedPreset) {
                PresetsView { preset in
                    pickedPreset = preset
                    showingPresets = false
                }
            }
            .fullScreenCover(item: $activeRun) { session in
                RunView(session: session)
            }
        }
    }

    private var list: some View {
        List {
            ForEach(templates) { template in
                TemplateRow(template: template) { start(template) }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { delete(template) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button { editorTarget = .existing(template) } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .leading) {
                        Button { duplicate(template) } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        .tint(.gray)
                    }
                    .contextMenu {
                        Button("Start", systemImage: "play.fill") { start(template) }
                        Button("Edit", systemImage: "pencil") { editorTarget = .existing(template) }
                        Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(template) }
                        Button("Delete", systemImage: "trash", role: .destructive) { delete(template) }
                    }
            }
            .onMove(perform: move)
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Actions

    private func newTimer() {
        editorTarget = .new(name: String(localized: "My timer"), definition: .simple(SimpleConfig()), color: .red)
    }

    /// Opens the editor once the presets sheet has fully closed (two sheets can't animate at once).
    private func openPickedPreset() {
        guard let preset = pickedPreset else { return }
        pickedPreset = nil
        editorTarget = .new(name: preset.name, definition: preset.definition, color: .red)
    }

    private func start(_ template: TimerTemplate) {
        template.lastUsedAt = Date()
        activeRun = RunSession(
            name: template.name,
            color: template.color,
            definition: template.definition,
            templateID: template.id,
            settings: settings
        )
    }

    private func duplicate(_ template: TimerTemplate) {
        let copy = TimerTemplate(
            name: String(localized: "\(template.name) copy"),
            definition: template.definition,
            color: template.color,
            sortOrder: (templates.map(\.sortOrder).max() ?? 0) + 1
        )
        modelContext.insert(copy)
        saveAndSync()
    }

    private func delete(_ template: TimerTemplate) {
        SyncCoordinator.shared.recordDeletion(of: template.id)
        modelContext.delete(template)
        saveAndSync()
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = templates
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, template) in ordered.enumerated() where template.sortOrder != index {
            template.sortOrder = index
            template.touch()
        }
        saveAndSync()
    }

    private func saveAndSync() {
        try? modelContext.save()
        SyncCoordinator.shared.libraryChanged()
    }
}

private struct TemplateRow: View {
    let template: TimerTemplate
    let onStart: () -> Void

    var body: some View {
        Button(action: onStart) {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(template.color.color)
                    .frame(width: 8, height: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(TimerSummary.describe(template.definition))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(template.color.color)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(template.name), \(TimerSummary.describe(template.definition))")
        .accessibilityHint("Starts the timer. Swipe for edit and delete.")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("timer-\(template.name)")
    }
}
