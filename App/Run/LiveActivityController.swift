import ActivityKit
import Foundation

/// Starts, updates and ends the workout's Live Activity (Lock Screen and
/// Dynamic Island). Updates are sent only when something visible changes:
/// a new phase, pause or resume. The countdown itself ticks on its own
/// because the activity is given the phase's end date.
@MainActor
final class LiveActivityController {
    private var activity: Activity<WorkoutActivityAttributes>?
    private var lastState: WorkoutActivityAttributes.ContentState?

    var isActive: Bool { activity != nil }

    /// Seconds from now to the phase end the system currently holds, for tests.
    var systemSecondsToPhaseEnd: Double? {
        activity?.content.state.phaseEnd.timeIntervalSinceNow
    }

    /// Phase name the system currently holds, for tests.
    var systemPhaseName: String? { activity?.content.state.phaseName }

    func start(name: String, color: ThemeColor, state: WorkoutActivityAttributes.ContentState) {
        guard activity == nil, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let attributes = WorkoutActivityAttributes(timerName: name, colorName: color.rawValue)
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: state.phaseEnd.addingTimeInterval(60))
            )
            lastState = state
        } catch {
            print("Live Activity unavailable: \(error)")
        }
    }

    /// Sends `state` if it differs in any way the user can see.
    func update(_ state: WorkoutActivityAttributes.ContentState) {
        guard let activity, needsUpdate(from: lastState, to: state) else { return }
        lastState = state
        let content = ActivityContent(state: state, staleDate: state.isPaused ? nil : state.phaseEnd.addingTimeInterval(60))
        Task { await activity.update(content) }
    }

    /// Ends the activity. A finished workout stays on the Lock Screen briefly.
    func end(_ state: WorkoutActivityAttributes.ContentState?, finished: Bool) {
        guard let activity else { return }
        self.activity = nil
        lastState = nil
        let content = state.map { ActivityContent(state: $0, staleDate: nil) }
        let policy: ActivityUIDismissalPolicy = finished ? .after(Date().addingTimeInterval(5 * 60)) : .immediate
        Task { await activity.end(content, dismissalPolicy: policy) }
    }

    /// Phase changes, pause/resume and finishing need an update; a running
    /// countdown drifting by a fraction of a second does not.
    private func needsUpdate(from old: WorkoutActivityAttributes.ContentState?, to new: WorkoutActivityAttributes.ContentState) -> Bool {
        guard let old else { return true }
        if old.phaseName != new.phaseName || old.phaseKind != new.phaseKind || old.round != new.round
            || old.cycle != new.cycle || old.isFinished != new.isFinished || old.isPaused != new.isPaused
            || old.nextName != new.nextName {
            return true
        }
        if new.isPaused { return false }
        return abs(old.phaseEnd.timeIntervalSince(new.phaseEnd)) > 1
    }
}
