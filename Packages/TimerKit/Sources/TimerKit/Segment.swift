import Foundation

/// The kind of phase a segment represents. Drives colour, voice and haptics.
public enum PhaseKind: String, Codable, CaseIterable, Sendable {
    case prepare
    case work
    case rest
    case cycleRest
    case coolDown

    /// Default spoken / displayed name (English). The app localises these.
    public var defaultName: String {
        switch self {
        case .prepare: return "Get ready"
        case .work: return "Work"
        case .rest: return "Rest"
        case .cycleRest: return "Cycle rest"
        case .coolDown: return "Cool down"
        }
    }

    /// Phases that count as "active" exercise time in history.
    public var isActive: Bool { self == .work }
}

/// One timed block of a workout. A workout is just an ordered list of segments.
public struct Segment: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var kind: PhaseKind
    /// Length in whole seconds. For a "tap when done" segment this is the
    /// time cap instead, and 0 means no cap.
    public var duration: Int
    /// Optional custom name, e.g. "Burpees". Spoken instead of the phase name when set.
    public var label: String?
    /// 1-based round within its cycle (0 when not applicable, e.g. prepare).
    public var round: Int
    /// 1-based cycle (0 when not applicable).
    public var cycle: Int
    /// Runs until the user taps Done (or the time cap passes), counting up.
    public var untilTapped: Bool
    /// AMRAP: the user taps once for every round they finish.
    public var countsRounds: Bool
    /// Custom timers: segments next to each other with the same group repeat together.
    public var group: RepeatGroup?
    /// Rounds in this segment's own block ("Round 2/3" in a repeat group).
    /// nil means use the plan's round count. Set when groups are expanded.
    public var roundsTotal: Int?

    public init(
        id: UUID = UUID(),
        kind: PhaseKind,
        duration: Int,
        label: String? = nil,
        round: Int = 0,
        cycle: Int = 0,
        untilTapped: Bool = false,
        countsRounds: Bool = false,
        group: RepeatGroup? = nil,
        roundsTotal: Int? = nil
    ) {
        self.id = id
        self.kind = kind
        self.duration = max(0, duration)
        self.label = label
        self.round = round
        self.cycle = cycle
        self.untilTapped = untilTapped
        self.countsRounds = countsRounds
        self.group = group
        self.roundsTotal = roundsTotal
    }

    /// Name to show and speak for this segment.
    public var displayName: String {
        if let label, !label.trimmingCharacters(in: .whitespaces).isEmpty { return label }
        return kind.defaultName
    }

    /// Waits for a tap with no time limit.
    public var isOpenEnded: Bool { untilTapped && duration == 0 }

    // Older files have none of the new keys; new keys are only written when
    // used, which keeps shared timers small enough for a QR code.
    private enum CodingKeys: String, CodingKey {
        case id, kind, duration, label, round, cycle
        case untilTapped = "tap"
        case countsRounds = "amrap"
        case group
        case roundsTotal
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(UUID.self, forKey: .id),
            kind: try c.decode(PhaseKind.self, forKey: .kind),
            duration: try c.decode(Int.self, forKey: .duration),
            label: try c.decodeIfPresent(String.self, forKey: .label),
            round: try c.decodeIfPresent(Int.self, forKey: .round) ?? 0,
            cycle: try c.decodeIfPresent(Int.self, forKey: .cycle) ?? 0,
            untilTapped: try c.decodeIfPresent(Bool.self, forKey: .untilTapped) ?? false,
            countsRounds: try c.decodeIfPresent(Bool.self, forKey: .countsRounds) ?? false,
            group: try c.decodeIfPresent(RepeatGroup.self, forKey: .group),
            roundsTotal: try c.decodeIfPresent(Int.self, forKey: .roundsTotal)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(kind, forKey: .kind)
        try c.encode(duration, forKey: .duration)
        try c.encodeIfPresent(label, forKey: .label)
        try c.encode(round, forKey: .round)
        try c.encode(cycle, forKey: .cycle)
        if untilTapped { try c.encode(true, forKey: .untilTapped) }
        if countsRounds { try c.encode(true, forKey: .countsRounds) }
        try c.encodeIfPresent(group, forKey: .group)
        try c.encodeIfPresent(roundsTotal, forKey: .roundsTotal)
    }
}

/// Marks a segment as part of a block that repeats ("these 3 exercises × 4").
public struct RepeatGroup: Codable, Hashable, Sendable {
    public var id: UUID
    public var repeats: Int

    public init(id: UUID = UUID(), repeats: Int = 2) {
        self.id = id
        self.repeats = max(1, repeats)
    }
}
