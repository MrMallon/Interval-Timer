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
        container = AppPersistence.container
        SyncCoordinator.shared.onLibraryChange = { AppPersistence.refreshExternalViews() }
        SyncCoordinator.shared.start(container: container)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(AppRouter.shared)
                .onOpenURL { AppRouter.shared.handle($0) }
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @AppStorage("didSeedPresets") private var didSeedPresets = false

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            LibraryView()
                .tabItem { Label("Timers", systemImage: "timer") }
                .tag(AppRouter.Tab.timers)
            StopwatchView()
                .tabItem { Label("Stopwatch", systemImage: "stopwatch") }
                .tag(AppRouter.Tab.stopwatch)
            HistoryView()
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(AppRouter.Tab.history)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppRouter.Tab.settings)
        }
        .onAppear {
            seedIfNeeded()
            AppPersistence.refreshExternalViews()
        }
        .overlay(alignment: .bottom) {
            if LaunchEnvironment.isUITesting {
                Text(verbatim: "url=\(router.lastURL) pending=\(router.pendingStart?.uuidString ?? "-")")
                    .font(.system(size: 2))
                    .opacity(0.02)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("routerLog")
            }
        }
    }

    /// First launch: give the library a few useful timers to start from.
    private func seedIfNeeded() {
        guard !didSeedPresets else { return }
        didSeedPresets = true
        for (offset, starter) in Preset.starters.enumerated() {
            guard let preset = Preset.all.first(where: { $0.id == starter.id }) else { continue }
            modelContext.insert(TimerTemplate(
                id: Preset.starterTemplateID(starter.id),
                name: PresetText.name(preset),
                definition: preset.definition,
                color: starter.color,
                sortOrder: offset
            ))
        }
        if LaunchEnvironment.isUITesting {
            // Short timers so UI tests finish quickly.
            modelContext.insert(TimerTemplate(
                id: UUID(uuidString: "7E570000-0000-4000-8000-000000000001")!,
                name: "Quick test",
                definition: .simple(SimpleConfig(prepare: 5, work: 4, rest: 3, rounds: 2, cycles: 1, restBetweenCycles: 0, coolDown: 0)),
                color: .green,
                sortOrder: -2
            ))
            modelContext.insert(TimerTemplate(
                id: UUID(uuidString: "7E570000-0000-4000-8000-000000000002")!,
                name: "Background test",
                definition: .simple(SimpleConfig(prepare: 2, work: 12, rest: 6, rounds: 2, cycles: 1, restBetweenCycles: 0, coolDown: 0)),
                color: .purple,
                sortOrder: -1
            ))
        }
        try? modelContext.save()
        SyncCoordinator.shared.libraryChanged()
    }
}
