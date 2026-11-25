import Foundation

/// An expanded, ready-to-run workout: the segment list plus precomputed
/// offsets so the engine can look up "where are we" for any elapsed time.
public struct WorkoutPlan: Hashable, Sendable {
    public let name: String
    public let segments: [Segment]
    /// Start offset (seconds from workout start) of each segment.
    public let startOffsets: [Int]
    /// Length of the timed part. A "tap when done" segment with no cap counts as 0
    /// until it is done, so this is the shortest the workout can be.
    public let totalDuration: Int
    /// Highest round number in any cycle (for "Round 3 / 8").
    public let roundsPerCycle: Int
    /// Number of cycles (for "Cycle 1 / 2").
    public let cycleCount: Int
    /// The first segment that waits for a tap with no time cap. The clock holds
    /// there, and nothing after it is timed yet, until the user taps Done.
    public let openIndex: Int?

    public init(name: String, segments: [Segment]) {
        let kept = segments.filter { $0.duration > 0 || $0.untilTapped }
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
        self.openIndex = kept.firstIndex(where: \.isOpenEnded)
    }

    public init(name: String, definition: TimerDefinition) {
        self.init(name: name, segments: definition.segments())
    }

    public var isEmpty: Bool { segments.isEmpty }

    /// True when some interval runs until the user taps Done.
    public var hasTapToFinish: Bool { segments.contains(where: \.untilTapped) }

    /// True when the user counts rounds (AMRAP).
    public var countsRounds: Bool { segments.contains(where: \.countsRounds) }

    /// Index of the segment running at `elapsed` seconds, or nil once finished.
    public func segmentIndex(at elapsed: TimeInterval) -> Int? {
        guard !segments.isEmpty else { return nil }
        let clamped = max(0, elapsed)
        if let openIndex, clamped >= TimeInterval(startOffsets[openIndex]) {
            return openIndex
        }
        guard clamped < TimeInterval(totalDuration) else { return nil }
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

    /// "Round 2/3" for this segment, or nil when it has no round counter.
    public func roundCounter(for segment: Segment) -> (round: Int, total: Int)? {
        if let total = segment.roundsTotal {
            guard total > 0, segment.round > 0 else { return nil }
            return (segment.round, total)
        }
        guard roundsPerCycle > 0 else { return nil }
        return (max(1, segment.round), roundsPerCycle)
    }

    /// Total seconds of work segments.
    public var totalWork: Int {
        segments.filter { $0.kind.isActive }.reduce(0) { $0 + $1.duration }
    }

    /// Number of work segments.
    public var workCount: Int {
        segments.filter { $0.kind == .work }.count
    }

    // MARK: - Results

    /// Seconds of work done by `elapsed`.
    public func workSeconds(upTo elapsed: TimeInterval) -> Double {
        var total: Double = 0
        for (index, segment) in segments.enumerated() where segment.kind.isActive {
            let start = Double(startOffsets[index])
            let end = index == openIndex ? .infinity : start + Double(segment.duration)
            total += max(0, min(end, elapsed) - start)
        }
        return total
    }

    /// Work segments fully finished by `elapsed`.
    public func workIntervalsDone(upTo elapsed: TimeInterval) -> Int {
        var count = 0
        for (index, segment) in segments.enumerated() where segment.kind == .work && index != openIndex {
            if Double(startOffsets[index] + segment.duration) <= elapsed + 0.001 { count += 1 }
        }
        return count
    }
}
