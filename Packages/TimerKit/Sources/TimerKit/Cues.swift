import Foundation

/// User preferences that shape the cue timeline and how cues are played.
public struct CueSettings: Codable, Hashable, Sendable {
    /// Short beeps on each phase change and on the final countdown.
    public var beeps: Bool
    /// Spoken phase names, countdowns and announcements.
    public var voice: Bool
    /// A quiet tick every second.
    public var ticking: Bool
    /// How many seconds to count down at the end of each segment (0 = off).
    public var countdownSeconds: Int
    /// Spoken "x minutes left" markers inside long segments.
    public var timeMarkers: Bool
    /// The marker points, in seconds before a segment ends.
    public var markerPoints: [Int]
    /// During rest, announce what comes next ("Next: round 4 of 8").
    public var announceNext: Bool
    /// Flash the whole screen on phase changes.
    public var flash: Bool
    /// Vibrate on phase changes and countdown.
    public var haptics: Bool
    /// Lower other apps' audio while speaking. Off by default: we mix, never duck.
    public var duckMusic: Bool

    public init(
        beeps: Bool = true,
        voice: Bool = true,
        ticking: Bool = false,
        countdownSeconds: Int = 3,
        timeMarkers: Bool = true,
        markerPoints: [Int] = [300, 60, 30],
        announceNext: Bool = true,
        flash: Bool = true,
        haptics: Bool = true,
        duckMusic: Bool = false
    ) {
        self.beeps = beeps
        self.voice = voice
        self.ticking = ticking
        self.countdownSeconds = max(0, min(10, countdownSeconds))
        self.timeMarkers = timeMarkers
        self.markerPoints = markerPoints
        self.announceNext = announceNext
        self.flash = flash
        self.haptics = haptics
        self.duckMusic = duckMusic
    }

    public static let `default` = CueSettings()

    /// True when nothing audible is enabled; the app then leaves the audio
    /// session completely alone so the user's music is never touched.
    public var isSilent: Bool { !beeps && !voice && !ticking }
}

/// Something that should happen at a moment in the workout.
public enum CueEvent: Hashable, Sendable {
    /// A segment begins (beep + spoken phase name + flash).
    case segmentStart(index: Int)
    /// Final countdown inside a segment: 3, 2, 1.
    case countdown(secondsLeft: Int, segmentIndex: Int)
    /// "30 seconds left" style marker.
    case timeRemaining(seconds: Int, segmentIndex: Int)
    /// During a rest, announce the upcoming segment.
    case upNext(segmentIndex: Int)
    /// Once-a-second tick.
    case tick(segmentIndex: Int)
    /// The workout is complete.
    case finished

    /// Ticks are dropped when late; everything else is replayed if it is the latest of its kind.
    var priority: Int {
        switch self {
        case .finished: return 5
        case .segmentStart: return 4
        case .countdown: return 3
        case .upNext: return 2
        case .timeRemaining: return 1
        case .tick: return 0
        }
    }
}

public struct ScheduledCue: Hashable, Sendable {
    /// Seconds from workout start.
    public let time: TimeInterval
    public let event: CueEvent

    public init(time: TimeInterval, event: CueEvent) {
        self.time = time
        self.event = event
    }
}

/// Builds the full cue timeline for a plan up front, so cues fire from a list
/// rather than being decided tick by tick.
public enum CuePlanner {
    /// Seconds before a segment ends at which "up next" is spoken, on top of the countdown.
    static let upNextLead = 4

    public static func cues(for plan: WorkoutPlan, settings: CueSettings) -> [ScheduledCue] {
        var cues: [ScheduledCue] = []
        let countdown = settings.countdownSeconds

        for (index, segment) in plan.segments.enumerated() {
            let start = plan.startOffsets[index]
            let end = start + segment.duration
            cues.append(ScheduledCue(time: TimeInterval(start), event: .segmentStart(index: index)))

            // Final countdown: never on the segment's very first second.
            let countdownLength = min(countdown, segment.duration - 1)
            var countdownTimes = Set<Int>()
            if countdownLength > 0 {
                for left in stride(from: countdownLength, through: 1, by: -1) {
                    let time = end - left
                    countdownTimes.insert(time)
                    cues.append(ScheduledCue(
                        time: TimeInterval(time),
                        event: .countdown(secondsLeft: left, segmentIndex: index)
                    ))
                }
            }

            // Time markers for long segments.
            var markerTimes = Set<Int>()
            for point in settings.markerPoints.sorted(by: >) where point > 0 {
                guard segment.duration > point + countdown + 5 else { continue }
                let time = end - point
                markerTimes.insert(time)
                cues.append(ScheduledCue(
                    time: TimeInterval(time),
                    event: .timeRemaining(seconds: point, segmentIndex: index)
                ))
            }

            // "Up next" during non-work segments that are followed by something.
            if segment.kind != .work, index + 1 < plan.segments.count {
                let lead = countdown + upNextLead
                if segment.duration >= lead + 2 {
                    let time = end - lead
                    if !markerTimes.contains(time) {
                        cues.append(ScheduledCue(time: TimeInterval(time), event: .upNext(segmentIndex: index + 1)))
                    }
                }
            }

            // Ticks on every other whole second.
            if segment.duration > 1 {
                for second in (start + 1)..<end where !countdownTimes.contains(second) {
                    cues.append(ScheduledCue(time: TimeInterval(second), event: .tick(segmentIndex: index)))
                }
            }
        }

        cues.append(ScheduledCue(time: TimeInterval(plan.totalDuration), event: .finished))
        return cues.sorted { lhs, rhs in
            if lhs.time != rhs.time { return lhs.time < rhs.time }
            return lhs.event.priority > rhs.event.priority
        }
    }
}

/// Walks the cue timeline as elapsed time advances and hands back what is due.
///
/// If the app was suspended and wakes up late, stale ticks, countdowns and
/// markers are dropped; only the latest segment start (and "finished") is
/// replayed so the user hears where they are now, not a burst of old cues.
public struct CueCursor: Sendable {
    public let cues: [ScheduledCue]
    /// Cues later than this are still pending.
    private var position: TimeInterval
    /// How late a cue may be and still play.
    public var staleAfter: TimeInterval

    public init(cues: [ScheduledCue], staleAfter: TimeInterval = 1.0) {
        self.cues = cues
        self.position = -.infinity
        self.staleAfter = staleAfter
    }

    /// Returns cues with `position < time <= elapsed`, minus stale ones.
    public mutating func advance(to elapsed: TimeInterval) -> [ScheduledCue] {
        guard elapsed > position else { return [] }
        let due = cues.filter { $0.time > position && $0.time <= elapsed }
        position = elapsed
        guard !due.isEmpty else { return [] }

        let fresh = due.filter { elapsed - $0.time <= staleAfter }
        let stale = due.filter { elapsed - $0.time > staleAfter }
        var result: [ScheduledCue] = []
        if let lastStart = stale.last(where: {
            if case .segmentStart = $0.event { return true }
            return false
        }), !fresh.contains(where: {
            if case .segmentStart = $0.event { return true }
            return false
        }) {
            result.append(lastStart)
        }
        if let finished = stale.first(where: { $0.event == .finished }) {
            result.append(finished)
        }
        result.append(contentsOf: fresh)
        return result
    }

    /// Repositions after a seek so the cue exactly at `elapsed` (a segment start) fires next.
    public mutating func jump(to elapsed: TimeInterval) {
        position = elapsed - 0.0001
    }

    /// Marks everything up to `elapsed` as already handled without returning it.
    public mutating func skip(to elapsed: TimeInterval) {
        position = elapsed
    }
}
