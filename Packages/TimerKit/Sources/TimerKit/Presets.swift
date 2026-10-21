import Foundation

/// A built-in starting point. Users copy a preset into their library and edit it.
public struct Preset: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let summary: String
    public let definition: TimerDefinition

    public init(id: String, name: String, summary: String, definition: TimerDefinition) {
        self.id = id
        self.name = name
        self.summary = summary
        self.definition = definition
    }

    public static let all: [Preset] = [
        Preset(
            id: "tabata",
            name: "Tabata",
            summary: "20 s work / 10 s rest × 8",
            definition: .simple(SimpleConfig(prepare: 10, work: 20, rest: 10, rounds: 8, cycles: 1, restBetweenCycles: 0, coolDown: 0))
        ),
        Preset(
            id: "hiit-40-20",
            name: "HIIT 40/20",
            summary: "40 s work / 20 s rest × 10",
            definition: .simple(SimpleConfig(prepare: 10, work: 40, rest: 20, rounds: 10, cycles: 1, restBetweenCycles: 0, coolDown: 60))
        ),
        Preset(
            id: "emom-10",
            name: "EMOM 10",
            summary: "Every minute on the minute, 10 min",
            definition: .simple(SimpleConfig(prepare: 10, work: 60, rest: 0, rounds: 10, cycles: 1, restBetweenCycles: 0, coolDown: 0))
        ),
        Preset(
            id: "boxing",
            name: "Boxing rounds",
            summary: "3 min rounds / 1 min rest × 12",
            definition: .simple(SimpleConfig(prepare: 10, work: 180, rest: 60, rounds: 12, cycles: 1, restBetweenCycles: 0, coolDown: 0))
        ),
        Preset(
            id: "mma",
            name: "MMA rounds",
            summary: "5 min rounds / 1 min rest × 5",
            definition: .simple(SimpleConfig(prepare: 10, work: 300, rest: 60, rounds: 5, cycles: 1, restBetweenCycles: 0, coolDown: 0))
        ),
        Preset(
            id: "circuit",
            name: "Circuit",
            summary: "45/15 × 6 stations, 3 cycles, 90 s between",
            definition: .simple(SimpleConfig(prepare: 10, work: 45, rest: 15, rounds: 6, cycles: 3, restBetweenCycles: 90, coolDown: 120))
        ),
        Preset(
            id: "physio",
            name: "Physio holds",
            summary: "10 s contract / 10 s relax × 6, 5 sets",
            definition: .simple(SimpleConfig(prepare: 5, work: 10, rest: 10, rounds: 6, cycles: 5, restBetweenCycles: 30, coolDown: 0))
        ),
        Preset(
            id: "pyramid",
            name: "Pyramid",
            summary: "20-30-40-50-40-30-20 s, 15 s rest",
            definition: .custom(Preset.pyramid(steps: [20, 30, 40, 50, 40, 30, 20], rest: 15, prepare: 10))
        )
    ]

    /// Builds a ladder/pyramid: one work segment per step with equal rests between.
    public static func pyramid(steps: [Int], rest: Int, prepare: Int) -> [Segment] {
        var segments: [Segment] = []
        if prepare > 0 { segments.append(Segment(kind: .prepare, duration: prepare)) }
        for (offset, step) in steps.enumerated() {
            let round = offset + 1
            segments.append(Segment(kind: .work, duration: step, round: round, cycle: 1))
            if round < steps.count, rest > 0 {
                segments.append(Segment(kind: .rest, duration: rest, round: round, cycle: 1))
            }
        }
        return segments
    }
}

public enum TimeFormat {
    /// "0:45", "3:00", "1:02:03". Rounds partial seconds up so a countdown
    /// shows 3, 2, 1 and reaches 0:00 exactly at the end.
    public static func countdown(_ seconds: TimeInterval) -> String {
        clock(Int(max(0, seconds).rounded(.up)))
    }

    /// Whole-second clock string, "m:ss" or "h:mm:ss".
    public static func clock(_ totalSeconds: Int) -> String {
        let value = max(0, totalSeconds)
        let hours = value / 3600
        let minutes = (value % 3600) / 60
        let seconds = value % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Stopwatch style with hundredths: "1:23.45".
    public static func stopwatch(_ seconds: TimeInterval) -> String {
        let value = max(0, seconds)
        let whole = Int(value)
        let hundredths = Int((value - TimeInterval(whole)) * 100)
        let minutes = whole / 60
        let secs = whole % 60
        if minutes >= 60 {
            return String(format: "%d:%02d:%02d.%02d", minutes / 60, minutes % 60, secs, hundredths)
        }
        return String(format: "%d:%02d.%02d", minutes, secs, hundredths)
    }
}
