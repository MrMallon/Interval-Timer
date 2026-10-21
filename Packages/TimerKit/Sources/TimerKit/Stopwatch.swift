import Foundation

/// Count-up interval stopwatch with laps. Clock-based like `TimerEngine`.
public struct Stopwatch: Sendable, Equatable {
    public enum Status: String, Codable, Sendable {
        case idle
        case running
        case paused
    }

    public private(set) var status: Status = .idle
    private var banked: TimeInterval = 0
    private var runStartedAt: TimeInterval?
    /// Elapsed time at each lap press.
    public private(set) var lapMarks: [TimeInterval] = []

    public init() {}

    public func elapsed(at now: TimeInterval) -> TimeInterval {
        var value = banked
        if let runStartedAt { value += max(0, now - runStartedAt) }
        return value
    }

    public mutating func start(at now: TimeInterval) {
        switch status {
        case .idle, .paused:
            runStartedAt = now
            status = .running
        case .running:
            break
        }
    }

    public mutating func pause(at now: TimeInterval) {
        guard status == .running else { return }
        banked = elapsed(at: now)
        runStartedAt = nil
        status = .paused
    }

    public mutating func lap(at now: TimeInterval) {
        guard status == .running else { return }
        lapMarks.append(elapsed(at: now))
    }

    public mutating func reset() {
        self = Stopwatch()
    }

    /// Completed lap durations, oldest first.
    public var laps: [TimeInterval] {
        var previous: TimeInterval = 0
        return lapMarks.map { mark in
            defer { previous = mark }
            return mark - previous
        }
    }

    /// Duration of the lap currently running.
    public func currentLap(at now: TimeInterval) -> TimeInterval {
        elapsed(at: now) - (lapMarks.last ?? 0)
    }
}
