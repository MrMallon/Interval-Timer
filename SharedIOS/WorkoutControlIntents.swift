import AppIntents
import Foundation

/// What the Lock Screen and Dynamic Island buttons ask a running workout to do.
enum WorkoutCommand: Sendable {
    case togglePause
    /// Next interval, or Done on an interval that waits for a tap.
    case next
    /// AMRAP: one more round finished.
    case countRound
}

/// The running workout registers here so the Live Activity's buttons can reach it.
/// The buttons' intents run inside the app (that's what `LiveActivityIntent` means),
/// so in the widget extension this is never set.
@MainActor
enum WorkoutRemote {
    private(set) static var owner: ObjectIdentifier?
    private static var handler: ((WorkoutCommand) -> Void)?

    static func register(_ owner: AnyObject, handler: @escaping (WorkoutCommand) -> Void) {
        self.owner = ObjectIdentifier(owner)
        self.handler = handler
    }

    static func unregister(_ owner: AnyObject) {
        guard self.owner == ObjectIdentifier(owner) else { return }
        self.owner = nil
        handler = nil
    }

    static func send(_ command: WorkoutCommand) {
        handler?(command)
    }
}

struct ToggleWorkoutPauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause or Resume Workout"
    static var isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await WorkoutRemote.send(.togglePause)
        return .result()
    }
}

struct NextIntervalIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Next Interval"
    static var isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await WorkoutRemote.send(.next)
        return .result()
    }
}

struct CountRoundIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Count a Round"
    static var isDiscoverable = false

    init() {}

    func perform() async throws -> some IntentResult {
        await WorkoutRemote.send(.countRound)
        return .result()
    }
}
