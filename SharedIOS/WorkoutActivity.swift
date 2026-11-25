import ActivityKit
import Foundation
import TimerKit

/// The Live Activity shown on the Lock Screen and in the Dynamic Island while
/// a workout runs. Shared by the app (which starts and updates it) and the
/// widget extension (which draws it).
struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Already-localised phase name, e.g. "Work" or "Burpees".
        var phaseName: String
        /// `PhaseKind.rawValue`, used for the colour and icon.
        var phaseKind: String
        var round: Int
        var roundsTotal: Int
        var cycle: Int
        var cyclesTotal: Int
        /// When the current phase started and ends (running only).
        var phaseStart: Date
        var phaseEnd: Date
        /// The clock value frozen on screen while paused (seconds left, or
        /// seconds so far when counting up); nil while running.
        var pausedRemaining: Double?
        /// Already-localised name of the next phase, if any.
        var nextName: String?
        var isFinished: Bool
        /// The phase waits for Done and its clock counts up. Optional so states
        /// saved by an older version still decode.
        var countsUp: Bool?
        /// AMRAP: show the round counter and its button.
        var countsRounds: Bool?
        var roundsCounted: Int?

        var isPaused: Bool { pausedRemaining != nil }
        var isCountingUp: Bool { countsUp ?? false }
        var isCountingRounds: Bool { countsRounds ?? false }
    }

    var timerName: String
    var colorName: String
}

extension WorkoutActivityAttributes.ContentState {
    /// Builds the Live Activity state from an engine snapshot.
    /// `now` is wall-clock time; `snapshot.remainingInSegment` is converted to an end date.
    static func make(
        snapshot: TimerSnapshot,
        plan: WorkoutPlan,
        now: Date,
        roundsCounted: Int = 0,
        phaseName: (Segment) -> String
    ) -> Self {
        let segment = snapshot.segment
        let remaining = snapshot.remainingInSegment
        let elapsedInPhase = snapshot.elapsedInSegment
        let countsUp = segment?.untilTapped ?? false
        let counter = segment.flatMap { plan.roundCounter(for: $0) }
        let phaseStart = now.addingTimeInterval(-elapsedInPhase)
        return Self(
            phaseName: segment.map(phaseName) ?? "",
            phaseKind: segment?.kind.rawValue ?? PhaseKind.work.rawValue,
            round: counter?.round ?? 1,
            roundsTotal: counter?.total ?? 0,
            cycle: max(1, segment?.cycle ?? 1),
            cyclesTotal: plan.cycleCount,
            phaseStart: phaseStart,
            // With no time limit there is no end: a fixed far-off date keeps the
            // activity from going stale and from needing an update every second.
            phaseEnd: segment?.isOpenEnded == true ? phaseStart.addingTimeInterval(12 * 3600) : now.addingTimeInterval(remaining),
            pausedRemaining: snapshot.status == .paused ? (countsUp ? elapsedInPhase : remaining) : nil,
            nextName: snapshot.nextSegment.map(phaseName),
            isFinished: snapshot.status == .finished,
            countsUp: countsUp,
            countsRounds: segment?.countsRounds ?? false,
            roundsCounted: roundsCounted
        )
    }
}
