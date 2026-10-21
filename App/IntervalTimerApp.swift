import SwiftData
import SwiftUI
import TimerKit

@main
struct IntervalTimerApp: App {
    @State private var settings: SettingsStore
    private let container: ModelContainer

    init() {
        if LaunchEnvironment.isUITesting, let bundleID = Bundle.main.bundleIdentifier {
            // Every UI test starts from a fresh install.
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        _settings = State(initialValue: SettingsStore())
        let configuration = ModelConfiguration(isStoredInMemoryOnly: LaunchEnvironment.usesInMemoryStore)
        do {
            container = try ModelContainer(for: TimerTemplate.self, WorkoutRecord.self, configurations: configuration)
        } catch {
            fatalError("Could not open the timer database: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("didSeedPresets") private var didSeedPresets = false

    var body: some View {
        TabView {
            LibraryView()
                .tabItem { Label("Timers", systemImage: "timer") }
            StopwatchView()
                .tabItem { Label("Stopwatch", systemImage: "stopwatch") }
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .onAppear(perform: seedIfNeeded)
    }

    /// First launch: give the library a few useful timers to start from.
    private func seedIfNeeded() {
        guard !didSeedPresets else { return }
        didSeedPresets = true
        let starters: [(String, ThemeColor)] = [("tabata", .red), ("hiit-40-20", .orange), ("boxing", .blue)]
        for (offset, starter) in starters.enumerated() {
            guard let preset = Preset.all.first(where: { $0.id == starter.0 }) else { continue }
            modelContext.insert(TimerTemplate(name: preset.name, definition: preset.definition, color: starter.1, sortOrder: offset))
        }
        if LaunchEnvironment.isUITesting {
            // Short timers so UI tests finish quickly.
            modelContext.insert(TimerTemplate(
                name: "Quick test",
                definition: .simple(SimpleConfig(prepare: 2, work: 4, rest: 2, rounds: 2, cycles: 1, restBetweenCycles: 0, coolDown: 0)),
                color: .green,
                sortOrder: -2
            ))
            modelContext.insert(TimerTemplate(
                name: "Background test",
                definition: .simple(SimpleConfig(prepare: 2, work: 12, rest: 6, rounds: 2, cycles: 1, restBetweenCycles: 0, coolDown: 0)),
                color: .purple,
                sortOrder: -1
            ))
        }
    }
}
