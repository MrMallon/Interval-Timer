import Foundation
import Observation
import SwiftData
import WidgetKit

/// Routes requests from outside the app (widget taps, Siri, Shortcuts) to the UI.
@Observable
@MainActor
final class AppRouter {
    static let shared = AppRouter()

    enum Tab: Hashable { case timers, stopwatch, history, settings }

    var selectedTab: Tab = .timers
    /// A timer the user asked to start from outside the app. LibraryView starts it and clears this.
    var pendingStart: UUID?

    func handle(_ url: URL) {
        guard let link = DeepLink(url: url) else { return }
        switch link {
        case .start(let id): start(id)
        }
    }

    func start(_ id: UUID) {
        selectedTab = .timers
        pendingStart = id
    }
}

/// The app's one database, shared by the UI and App Intents (Siri, Shortcuts).
enum AppPersistence {
    static let container: ModelContainer = {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: LaunchEnvironment.usesInMemoryStore)
        do {
            return try ModelContainer(for: TimerTemplate.self, WorkoutRecord.self, configurations: configuration)
        } catch {
            fatalError("Could not open the timer database: \(error)")
        }
    }()

    /// Refreshes everything outside the app that mirrors the timer list:
    /// the home-screen widget and Siri's list of timer names.
    @MainActor
    static func refreshExternalViews() {
        let templates = (try? container.mainContext.fetch(
            FetchDescriptor<TimerTemplate>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)])
        )) ?? []
        WidgetStore.save(templates.map {
            WidgetTimer(id: $0.id, name: $0.name, colorName: $0.colorName, summary: TimerSummary.describe($0.definition))
        })
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetStore.widgetKind)
        IntervalTimerShortcuts.updateAppShortcutParameters()
    }
}
