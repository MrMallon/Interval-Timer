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
        /// Seconds left in the phase when paused; nil while running.
        var pausedRemaining: Double?
        /// Already-localised name of the next phase, if any.
        var nextName: String?
        var isFinished: Bool

        var isPaused: Bool { pausedRemaining != nil }
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
        phaseName: (Segment) -> String
    ) -> Self {
        let segment = snapshot.segment
        let remaining = snapshot.remainingInSegment
        let elapsedInPhase = snapshot.elapsedInSegment
        return Self(
            phaseName: segment.map(phaseName) ?? "",
            phaseKind: segment?.kind.rawValue ?? PhaseKind.work.rawValue,
            round: max(1, segment?.round ?? 1),
            roundsTotal: plan.roundsPerCycle,
            cycle: max(1, segment?.cycle ?? 1),
            cyclesTotal: plan.cycleCount,
            phaseStart: now.addingTimeInterval(-elapsedInPhase),
            phaseEnd: now.addingTimeInterval(remaining),
            pausedRemaining: snapshot.status == .paused ? remaining : nil,
            nextName: snapshot.nextSegment.map(phaseName),
            isFinished: snapshot.status == .finished
        )
    }
}
