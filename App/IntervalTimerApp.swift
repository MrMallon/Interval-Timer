import SwiftData
import SwiftUI
import TimerKit

@main
struct IntervalTimerApp: App {
    @State private var settings = SettingsStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
        }
        .modelContainer(for: [TimerTemplate.self, WorkoutRecord.self])
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
    }
}
