import Foundation

/// The classic interval layout: prepare, then cycles of (work + rest) rounds,
/// with an optional longer rest between cycles and a cool-down at the end.
/// All durations are in whole seconds.
public struct SimpleConfig: Codable, Hashable, Sendable {
    public var prepare: Int
    public var work: Int
    public var rest: Int
    public var rounds: Int
    public var cycles: Int
    public var restBetweenCycles: Int
    public var coolDown: Int

    public init(
        prepare: Int = 10,
        work: Int = 30,
        rest: Int = 15,
        rounds: Int = 8,
        cycles: Int = 1,
        restBetweenCycles: Int = 60,
        coolDown: Int = 0
    ) {
        self.prepare = max(0, prepare)
        self.work = max(1, work)
        self.rest = max(0, rest)
        self.rounds = max(1, rounds)
        self.cycles = max(1, cycles)
        self.restBetweenCycles = max(0, restBetweenCycles)
        self.coolDown = max(0, coolDown)
    }

    /// Expands the config into an ordered list of segments.
    ///
    /// Rules:
    /// - `prepare` runs once at the start when > 0.
    /// - Every round has a work segment. A rest follows every round except the
    ///   last round of the last cycle (no point resting before the cool-down / end).
    /// - Between cycles the last round's rest is replaced by `restBetweenCycles`
    ///   when that is > 0 (otherwise the normal rest is kept).
    /// - `coolDown` runs once at the end when > 0.
    public func segments() -> [Segment] {
        var result: [Segment] = []
        if prepare > 0 {
            result.append(Segment(kind: .prepare, duration: prepare))
        }
        for cycle in 1...cycles {
            for round in 1...rounds {
                result.append(Segment(kind: .work, duration: work, round: round, cycle: cycle))

                let isLastRound = round == rounds
                let isLastCycle = cycle == cycles
                if isLastRound && isLastCycle { continue }

                if isLastRound && restBetweenCycles > 0 {
                    result.append(Segment(kind: .cycleRest, duration: restBetweenCycles, round: round, cycle: cycle))
                } else if rest > 0 {
                    result.append(Segment(kind: .rest, duration: rest, round: round, cycle: cycle))
                }
            }
        }
        if coolDown > 0 {
            result.append(Segment(kind: .coolDown, duration: coolDown))
        }
        return result
    }

    /// Total running time in seconds.
    public var totalDuration: Int {
        segments().reduce(0) { $0 + $1.duration }
    }
}

/// How a saved timer is defined: either the simple layout or a fully custom
/// list of segments (pyramids, ladders, named exercises).
public enum TimerDefinition: Codable, Hashable, Sendable {
    case simple(SimpleConfig)
    case custom([Segment])

    public func segments() -> [Segment] {
        switch self {
        case .simple(let config): return config.segments()
        case .custom(let segments): return segments.filter { $0.duration > 0 }
        }
    }
}
