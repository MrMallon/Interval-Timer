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
    /// Length in whole seconds.
    public var duration: Int
    /// Optional custom name, e.g. "Burpees". Spoken instead of the phase name when set.
    public var label: String?
    /// 1-based round within its cycle (0 when not applicable, e.g. prepare).
    public var round: Int
    /// 1-based cycle (0 when not applicable).
    public var cycle: Int

    public init(
        id: UUID = UUID(),
        kind: PhaseKind,
        duration: Int,
        label: String? = nil,
        round: Int = 0,
        cycle: Int = 0
    ) {
        self.id = id
        self.kind = kind
        self.duration = max(0, duration)
        self.label = label
        self.round = round
        self.cycle = cycle
    }

    /// Name to show and speak for this segment.
    public var displayName: String {
        if let label, !label.trimmingCharacters(in: .whitespaces).isEmpty { return label }
        return kind.defaultName
    }
}
