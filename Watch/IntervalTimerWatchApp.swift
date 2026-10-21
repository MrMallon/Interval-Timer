import SwiftData
import SwiftUI

@main
struct IntervalTimerWatchApp: App {
    @State private var settings: SettingsStore
    private let container: ModelContainer

    init() {
        _settings = State(initialValue: SettingsStore())
        let configuration = ModelConfiguration(isStoredInMemoryOnly: LaunchEnvironment.usesInMemoryStore)
        do {
            container = try ModelContainer(for: TimerTemplate.self, WorkoutRecord.self, configurations: configuration)
        } catch {
            fatalError("Could not open the timer database: \(error)")
        }
        SyncCoordinator.shared.start(container: container)
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(settings)
        }
        .modelContainer(container)
    }
}

struct WatchRootView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("didSeedPresets") private var didSeedPresets = false

    var body: some View {
        WatchLibraryView()
            .onAppear(perform: seedIfNeeded)
    }

    /// Same starter timers as the iPhone, with the same ids, so sync doesn't duplicate them.
    private func seedIfNeeded() {
        guard !didSeedPresets else { return }
        didSeedPresets = true
        for (offset, starter) in Preset.starters.enumerated() {
            guard let preset = Preset.all.first(where: { $0.id == starter.id }) else { continue }
            let id = Preset.starterTemplateID(starter.id)
            let existing = (try? modelContext.fetchCount(FetchDescriptor<TimerTemplate>(predicate: #Predicate { $0.id == id }))) ?? 0
            guard existing == 0 else { continue }
            modelContext.insert(TimerTemplate(id: id, name: preset.name, definition: preset.definition, color: starter.color, sortOrder: offset))
        }
        try? modelContext.save()
        SyncCoordinator.shared.libraryChanged()
    }
}
