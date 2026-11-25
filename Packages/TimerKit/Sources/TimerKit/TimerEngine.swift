import Foundation

/// A point-in-time view of a running workout, derived purely from the clock.
public struct TimerSnapshot: Equatable, Sendable {
    public let status: TimerEngine.Status
    /// Seconds since the workout started, excluding paused time.
    public let elapsed: TimeInterval
    public let segmentIndex: Int?
    public let segment: Segment?
    public let nextSegment: Segment?
    public let elapsedInSegment: TimeInterval
    public let remainingInSegment: TimeInterval
    public let totalRemaining: TimeInterval
    /// 0...1 progress through the current segment.
    public let segmentProgress: Double
    /// 0...1 progress through the whole workout.
    public let totalProgress: Double

    public var isFinished: Bool { status == .finished }
}

/// Deterministic workout state machine.
///
/// The engine never counts ticks. It stores when the current run started and
/// how much time was banked before it, so its state is a pure function of
/// "now". That keeps it exact across backgrounding, locking, interruptions and
/// a stalled UI. Callers pass `now` from a monotonic-enough clock
/// (`Date().timeIntervalSinceReferenceDate` in the app, a fake clock in tests).
public struct TimerEngine: Sendable {
    public enum Status: String, Codable, Sendable {
        case idle
        case running
        case paused
        case finished
    }

    /// Changes only when the user adds time to the current interval.
    public private(set) var plan: WorkoutPlan
    public private(set) var status: Status = .idle
    /// Elapsed seconds banked before the current run began.
    private var banked: TimeInterval = 0
    /// Clock time at which the current run began (nil unless running).
    private var runStartedAt: TimeInterval?

    public init(plan: WorkoutPlan) {
        self.plan = plan
    }

    private var total: TimeInterval { TimeInterval(plan.totalDuration) }

    // MARK: - Time

    public func elapsed(at now: TimeInterval) -> TimeInterval {
        var value = banked
        if let runStartedAt {
            value += max(0, now - runStartedAt)
        }
        value = max(0, value)
        // Waiting for a tap: the clock keeps counting inside that interval.
        if let open = plan.openIndex, value >= TimeInterval(plan.startOffsets[open]) {
            return value
        }
        return min(value, total)
    }

    /// The workout ends once the clock passes the end, unless an interval is still waiting for a tap.
    private func isPastEnd(_ elapsed: TimeInterval) -> Bool {
        plan.openIndex == nil && elapsed >= total
    }

    // MARK: - Controls

    public mutating func start(at now: TimeInterval) {
        guard status == .idle else { return }
        if plan.isEmpty {
            status = .finished
            return
        }
        banked = 0
        runStartedAt = now
        status = .running
    }

    public mutating func pause(at now: TimeInterval) {
        guard status == .running else { return }
        banked = elapsed(at: now)
        runStartedAt = nil
        status = .paused
        update(at: now)
    }

    public mutating func resume(at now: TimeInterval) {
        guard status == .paused else { return }
        runStartedAt = now
        status = .running
    }

    public mutating func togglePause(at now: TimeInterval) {
        switch status {
        case .running: pause(at: now)
        case .paused: resume(at: now)
        case .idle: start(at: now)
        case .finished: break
        }
    }

    /// Jumps to the start of the next segment, or finishes if there is none.
    /// On a "tap when done" interval this is Done: the time taken is kept.
    public mutating func skipForward(at now: TimeInterval) {
        guard status == .running || status == .paused else { return }
        guard let index = plan.segmentIndex(at: elapsed(at: now)) else { return }
        if plan.segments[index].untilTapped {
            completeCurrentSegment(at: now)
            return
        }
        let next = index + 1
        if next < plan.segments.count {
            seek(to: TimeInterval(plan.startOffsets[next]), at: now)
        } else {
            seek(to: total, at: now)
        }
    }

    /// Restarts the current segment, or goes to the previous one if the current
    /// segment started less than 2 seconds ago.
    public mutating func skipBackward(at now: TimeInterval) {
        guard status == .running || status == .paused else { return }
        let current = elapsed(at: now)
        guard let index = plan.segmentIndex(at: current) else { return }
        let start = TimeInterval(plan.startOffsets[index])
        if current - start < 2, index > 0 {
            seek(to: TimeInterval(plan.startOffsets[index - 1]), at: now)
        } else {
            seek(to: start, at: now)
        }
    }

    /// Moves to an absolute elapsed position, keeping the running/paused state.
    public mutating func seek(to position: TimeInterval, at now: TimeInterval) {
        guard status == .running || status == .paused else { return }
        banked = min(max(0, position), total)
        if status == .running {
            runStartedAt = now
        }
        update(at: now)
    }

    /// Adds time to the segment running now ("+10 s"), keeping the position in it.
    /// Later segments move back by the same amount. Returns false when nothing is running.
    @discardableResult
    public mutating func extendCurrentSegment(by seconds: Int, at now: TimeInterval) -> Bool {
        guard status == .running || status == .paused, seconds > 0 else { return false }
        let position = elapsed(at: now)
        guard let index = plan.segmentIndex(at: position), !plan.segments[index].isOpenEnded else { return false }
        var segments = plan.segments
        segments[index].duration += seconds
        plan = WorkoutPlan(name: plan.name, segments: segments)
        // Re-anchor so elapsed is unchanged under the longer plan.
        banked = position
        if status == .running { runStartedAt = now }
        return true
    }

    /// Done: ends the "tap when done" interval running now and moves on. Its
    /// length becomes the time it took (rounded up to a whole second).
    /// Returns false when the current interval isn't one that waits for a tap.
    @discardableResult
    public mutating func completeCurrentSegment(at now: TimeInterval) -> Bool {
        guard status == .running || status == .paused else { return false }
        let position = elapsed(at: now)
        guard let index = plan.segmentIndex(at: position), plan.segments[index].untilTapped else { return false }
        let start = plan.startOffsets[index]
        var taken = max(1, Int((position - TimeInterval(start)).rounded(.up)))
        let cap = plan.segments[index].duration
        if cap > 0 { taken = min(taken, cap) }
        var segments = plan.segments
        segments[index].duration = taken
        // Done, so it no longer holds the clock.
        segments[index].untilTapped = false
        plan = WorkoutPlan(name: plan.name, segments: segments)
        banked = TimeInterval(start + taken)
        if status == .running { runStartedAt = now }
        update(at: now)
        return true
    }

    public mutating func reset() {
        banked = 0
        runStartedAt = nil
        status = .idle
    }

    /// Marks the workout finished once the clock passes its end.
    /// Returns true on the call that performs the transition.
    @discardableResult
    public mutating func update(at now: TimeInterval) -> Bool {
        guard status == .running || status == .paused else { return false }
        if isPastEnd(elapsed(at: now)) {
            banked = total
            runStartedAt = nil
            status = .finished
            return true
        }
        return false
    }

    // MARK: - Snapshot

    public func snapshot(at now: TimeInterval) -> TimerSnapshot {
        let elapsed = elapsed(at: now)
        let effectiveStatus: Status = (status == .running || status == .paused) && isPastEnd(elapsed)
            ? .finished : status
        let index = effectiveStatus == .finished ? nil : plan.segmentIndex(at: elapsed)
        let segment = index.map { plan.segments[$0] }
        let next: Segment? = index.flatMap { $0 + 1 < plan.segments.count ? plan.segments[$0 + 1] : nil }

        var inSegment: TimeInterval = 0
        var remaining: TimeInterval = 0
        var progress: Double = 0
        if let index, let segment {
            inSegment = elapsed - TimeInterval(plan.startOffsets[index])
            if segment.isOpenEnded {
                remaining = 0
                progress = 0
            } else {
                remaining = max(0, TimeInterval(segment.duration) - inSegment)
                progress = segment.duration > 0 ? min(1, inSegment / TimeInterval(segment.duration)) : 1
            }
        }
        // Only the timed part is known while an interval waits for a tap.
        let timedElapsed = plan.openIndex.map { min(elapsed, TimeInterval(plan.startOffsets[$0])) } ?? elapsed

        return TimerSnapshot(
            status: effectiveStatus,
            elapsed: elapsed,
            segmentIndex: index,
            segment: segment,
            nextSegment: next,
            elapsedInSegment: inSegment,
            remainingInSegment: remaining,
            totalRemaining: max(0, total - timedElapsed),
            segmentProgress: progress,
            totalProgress: total > 0 ? min(1, timedElapsed / total) : 1
        )
    }
}
