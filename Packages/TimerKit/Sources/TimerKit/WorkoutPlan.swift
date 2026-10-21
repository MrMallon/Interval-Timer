import Foundation

/// An expanded, ready-to-run workout: the segment list plus precomputed
/// offsets so the engine can look up "where are we" for any elapsed time.
public struct WorkoutPlan: Hashable, Sendable {
    public let name: String
    public let segments: [Segment]
    /// Start offset (seconds from workout start) of each segment.
    public let startOffsets: [Int]
    public let totalDuration: Int
    /// Highest round number in any cycle (for "Round 3 / 8").
    public let roundsPerCycle: Int
    /// Number of cycles (for "Cycle 1 / 2").
    public let cycleCount: Int

    public init(name: String, segments: [Segment]) {
        let kept = segments.filter { $0.duration > 0 }
        self.name = name
        self.segments = kept
        var offsets: [Int] = []
        var running = 0
        for segment in kept {
            offsets.append(running)
            running += segment.duration
        }
        self.startOffsets = offsets
        self.totalDuration = running
        self.roundsPerCycle = kept.map(\.round).max() ?? 0
        self.cycleCount = kept.map(\.cycle).max() ?? 0
    }

    public init(name: String, definition: TimerDefinition) {
        self.init(name: name, segments: definition.segments())
    }

    public var isEmpty: Bool { segments.isEmpty }

    /// Index of the segment running at `elapsed` seconds, or nil once finished.
    public func segmentIndex(at elapsed: TimeInterval) -> Int? {
        guard !segments.isEmpty, elapsed < TimeInterval(totalDuration) else { return nil }
        let clamped = max(0, elapsed)
        // Binary search over start offsets.
        var low = 0
        var high = startOffsets.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if TimeInterval(startOffsets[mid]) <= clamped {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low
    }

    /// Total seconds of work segments.
    public var totalWork: Int {
        segments.filter { $0.kind.isActive }.reduce(0) { $0 + $1.duration }
    }

    /// Number of work segments.
    public var workCount: Int {
        segments.filter { $0.kind == .work }.count
    }
}
