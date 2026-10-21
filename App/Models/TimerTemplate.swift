import Foundation
import SwiftData
import TimerKit

/// A saved timer in the user's library. Edits update it in place.
@Model
final class TimerTemplate {
    var id: UUID = UUID()
    var name: String = ""
    var colorName: String = ThemeColor.red.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var sortOrder: Int = 0
    var lastUsedAt: Date?
    /// JSON-encoded `TimerDefinition`.
    var definitionData: Data = Data()

    init(name: String, definition: TimerDefinition, color: ThemeColor = .red, sortOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.colorName = color.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
        self.sortOrder = sortOrder
        self.definitionData = (try? JSONEncoder().encode(definition)) ?? Data()
    }

    var definition: TimerDefinition {
        get {
            (try? JSONDecoder().decode(TimerDefinition.self, from: definitionData)) ?? .simple(SimpleConfig())
        }
        set {
            definitionData = (try? JSONEncoder().encode(newValue)) ?? definitionData
            updatedAt = Date()
        }
    }

    var color: ThemeColor {
        get { ThemeColor(rawValue: colorName) ?? .red }
        set { colorName = newValue.rawValue }
    }

    var plan: WorkoutPlan {
        WorkoutPlan(name: name, definition: definition)
    }
}

/// One finished (or ended-early) workout or stopwatch session.
@Model
final class WorkoutRecord {
    enum Kind: String, Codable {
        case interval
        case stopwatch
    }

    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = Kind.interval.rawValue
    var colorName: String = ThemeColor.red.rawValue
    var startedAt: Date = Date()
    var endedAt: Date = Date()
    /// Seconds actually run (excludes pauses).
    var totalSeconds: Double = 0
    var workSeconds: Double = 0
    var roundsCompleted: Int = 0
    var totalRounds: Int = 0
    var completed: Bool = false
    /// Snapshot of the timer as it was run, so "Start again" stays accurate after edits.
    var definitionData: Data?
    /// Stopwatch lap durations, JSON-encoded `[Double]`.
    var lapsData: Data?

    init(
        name: String,
        kind: Kind,
        color: ThemeColor,
        startedAt: Date,
        endedAt: Date,
        totalSeconds: Double,
        workSeconds: Double = 0,
        roundsCompleted: Int = 0,
        totalRounds: Int = 0,
        completed: Bool,
        definition: TimerDefinition? = nil,
        laps: [Double]? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.kindRaw = kind.rawValue
        self.colorName = color.rawValue
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.totalSeconds = totalSeconds
        self.workSeconds = workSeconds
        self.roundsCompleted = roundsCompleted
        self.totalRounds = totalRounds
        self.completed = completed
        self.definitionData = definition.flatMap { try? JSONEncoder().encode($0) }
        self.lapsData = laps.flatMap { try? JSONEncoder().encode($0) }
    }

    var kind: Kind { Kind(rawValue: kindRaw) ?? .interval }
    var color: ThemeColor { ThemeColor(rawValue: colorName) ?? .red }

    var definition: TimerDefinition? {
        definitionData.flatMap { try? JSONDecoder().decode(TimerDefinition.self, from: $0) }
    }

    var laps: [Double] {
        lapsData.flatMap { try? JSONDecoder().decode([Double].self, from: $0) } ?? []
    }
}
