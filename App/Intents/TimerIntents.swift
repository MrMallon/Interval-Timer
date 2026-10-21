import AppIntents
import Foundation
import SwiftData

/// A saved timer, as Siri and Shortcuts see it.
struct TimerEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Timer")
    static var defaultQuery = TimerEntityQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name))
    }
}

struct TimerEntityQuery: EntityQuery, EntityStringQuery {
    @MainActor
    private func all() -> [TimerEntity] {
        let templates = (try? AppPersistence.container.mainContext.fetch(
            FetchDescriptor<TimerTemplate>(sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)])
        )) ?? []
        return templates.map { TimerEntity(id: $0.id, name: $0.name) }
    }

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [TimerEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func entities(matching string: String) async throws -> [TimerEntity] {
        all().filter { $0.name.localizedCaseInsensitiveContains(string) }
    }

    @MainActor
    func suggestedEntities() async throws -> [TimerEntity] {
        all()
    }
}

/// "Start Tabata in Interval Timer" — opens the app and starts that timer.
struct StartTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Timer"
    static var description = IntentDescription("Opens Interval Timer and starts one of your saved timers.")
    static var openAppWhenRun = true

    @Parameter(title: "Timer")
    var timer: TimerEntity

    init() {}

    init(timer: TimerEntity) {
        self.timer = timer
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.start(timer.id)
        return .result()
    }
}

struct IntervalTimerShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartTimerIntent(),
            phrases: [
                "Start \(\.$timer) in \(.applicationName)",
                "Start my \(\.$timer) timer in \(.applicationName)",
                "Start a timer in \(.applicationName)"
            ],
            shortTitle: "Start Timer",
            systemImageName: "timer"
        )
    }

    static var shortcutTileColor: ShortcutTileColor = .red
}
