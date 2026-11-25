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
    /// A timer someone shared (file or QR link). LibraryView opens it in the editor and clears this.
    var pendingImport: SharedTimer?
    /// Siri, the widget or a link asked to run the last workout again.
    var pendingRepeat = false
    /// Last link received, shown to UI tests.
    private(set) var lastURL = ""

    func handle(_ url: URL) {
        lastURL = url.absoluteString
        if url.isFileURL {
            if let timer = SharedTimer.from(fileURL: url) { receive(timer) }
            return
        }
        if let timer = SharedTimer.from(link: url) {
            receive(timer)
            return
        }
        guard let link = DeepLink(url: url) else { return }
        switch link {
        case .start(let id): start(id)
        case .repeatLast: repeatLast()
        }
    }

    private func receive(_ timer: SharedTimer) {
        selectedTab = .timers
        pendingImport = timer
    }

    func repeatLast() {
        selectedTab = .timers
        pendingRepeat = true
    }

    func start(_ id: UUID) {
        selectedTab = .timers
        pendingStart = id
    }
}

/// The app's one database, shared by the UI and App Intents (Siri, Shortcuts).
enum AppPersistence {
    /// The most recent interval workout that can be run again.
    @MainActor
    static func lastWorkout() -> WorkoutRecord? {
        let interval = WorkoutRecord.Kind.interval.rawValue
        var descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate { $0.kindRaw == interval && $0.definitionData != nil },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return (try? container.mainContext.fetch(descriptor))?.first
    }

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
        WidgetStore.saveLast(lastWorkout().map {
            WidgetTimer(id: $0.id, name: $0.name, colorName: $0.colorName, summary: $0.definition.map(TimerSummary.describe) ?? "")
        })
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetStore.widgetKind)
        IntervalTimerShortcuts.updateAppShortcutParameters()
    }
}
