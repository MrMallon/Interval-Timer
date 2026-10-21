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

    init(id: UUID = UUID(), name: String, definition: TimerDefinition, color: ThemeColor = .red, sortOrder: Int = 0) {
        self.id = id
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

    /// Marks a change (rename, recolour, reorder) so sync knows this copy is newest.
    func touch() {
        updatedAt = Date()
    }

    /// This timer as sent to the other device.
    var synced: SyncedTimer {
        SyncedTimer(id: id, name: name, colorName: colorName, sortOrder: sortOrder, definition: definition, updatedAt: updatedAt)
    }

    /// Overwrites this timer with a newer copy from the other device.
    func apply(_ remote: SyncedTimer) {
        name = remote.name
        colorName = remote.colorName
        sortOrder = remote.sortOrder
        definitionData = (try? JSONEncoder().encode(remote.definition)) ?? definitionData
        updatedAt = remote.updatedAt
    }
}

extension Preset {
    /// Starter timers get the same id on every device, so iPhone and Watch
    /// don't each sync over a second copy of Tabata.
    static func starterTemplateID(_ presetID: String) -> UUID {
        switch presetID {
        case "tabata": return UUID(uuidString: "5EED0000-0000-4000-8000-000000000001")!
        case "hiit-40-20": return UUID(uuidString: "5EED0000-0000-4000-8000-000000000002")!
        case "boxing": return UUID(uuidString: "5EED0000-0000-4000-8000-000000000003")!
        default: return UUID()
        }
    }

    /// The timers a new library starts with.
    static let starters: [(id: String, color: ThemeColor)] = [("tabata", .red), ("hiit-40-20", .orange), ("boxing", .blue)]
}

/// Converts a finished workout to and from the dictionary sent between devices.
extension WorkoutRecord {
    var transferPayload: [String: Any] {
        var payload: [String: Any] = [
            "id": id.uuidString,
            "name": name,
            "kind": kindRaw,
            "color": colorName,
            "startedAt": startedAt.timeIntervalSince1970,
            "endedAt": endedAt.timeIntervalSince1970,
            "totalSeconds": totalSeconds,
            "workSeconds": workSeconds,
            "roundsCompleted": roundsCompleted,
            "totalRounds": totalRounds,
            "completed": completed
        ]
        if let definitionData { payload["definition"] = definitionData }
        if let lapsData { payload["laps"] = lapsData }
        return payload
    }

    static func fromTransfer(_ payload: [String: Any]) -> WorkoutRecord? {
        guard
            let idString = payload["id"] as? String, let id = UUID(uuidString: idString),
            let name = payload["name"] as? String,
            let started = payload["startedAt"] as? Double,
            let ended = payload["endedAt"] as? Double
        else { return nil }
        let record = WorkoutRecord(
            name: name,
            kind: Kind(rawValue: payload["kind"] as? String ?? "") ?? .interval,
            color: ThemeColor(rawValue: payload["color"] as? String ?? "") ?? .red,
            startedAt: Date(timeIntervalSince1970: started),
            endedAt: Date(timeIntervalSince1970: ended),
            totalSeconds: payload["totalSeconds"] as? Double ?? 0,
            workSeconds: payload["workSeconds"] as? Double ?? 0,
            roundsCompleted: payload["roundsCompleted"] as? Int ?? 0,
            totalRounds: payload["totalRounds"] as? Int ?? 0,
            completed: payload["completed"] as? Bool ?? false
        )
        record.id = id
        record.definitionData = payload["definition"] as? Data
        record.lapsData = payload["laps"] as? Data
        return record
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
