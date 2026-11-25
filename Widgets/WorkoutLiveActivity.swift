import ActivityKit
import SwiftUI
import TimerKit
import WidgetKit

/// Lock Screen banner and Dynamic Island for a running workout.
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(phaseColor(context.state))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(state.phaseName)
                            .font(.headline)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: symbol(state))
                            .foregroundStyle(phaseColor(state))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Countdown(state: state)
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        HStack {
                            Text(context.attributes.timerName)
                                .lineLimit(1)
                            Spacer()
                            Text(counterText(state))
                                .monospacedDigit()
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        if !state.isFinished {
                            ActivityControls(state: state, fill: phaseColor(state))
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: symbol(state))
                    .foregroundStyle(phaseColor(state))
            } compactTrailing: {
                Countdown(state: state)
                    .frame(maxWidth: 52)
                    .foregroundStyle(phaseColor(state))
            } minimal: {
                Image(systemName: symbol(state))
                    .foregroundStyle(phaseColor(state))
            }
            .keylineTint(phaseColor(state))
        }
    }
}

private struct LockScreenView: View {
    let attributes: WorkoutActivityAttributes
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 12) {
            summary
            if !state.isFinished {
                ActivityControls(state: state, fill: .white.opacity(0.22))
            }
        }
        .foregroundStyle(.white)
        .padding(16)
    }

    private var summary: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text(state.isFinished ? String(localized: "Workout complete") : state.phaseName)
                        .font(.headline)
                        .lineLimit(1)
                } icon: {
                    Image(systemName: state.isFinished ? "checkmark.seal.fill" : symbol(state))
                }
                Text(attributes.timerName)
                    .font(.subheadline)
                    .lineLimit(1)
                if !state.isFinished {
                    Text(counterText(state))
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 8)
            if !state.isFinished {
                VStack(alignment: .trailing, spacing: 2) {
                    Countdown(state: state)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    if state.isPaused {
                        Text("Paused")
                            .font(.caption.weight(.semibold))
                    } else if let next = state.nextName {
                        Text(String(localized: "Next: \(next)"))
                            .font(.caption)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

/// Pause/Resume, Next (Done on an interval that waits for a tap) and, in an
/// AMRAP, "+1 round". The taps run in the app through `LiveActivityIntent`s.
private struct ActivityControls: View {
    let state: WorkoutActivityAttributes.ContentState
    let fill: Color

    var body: some View {
        HStack(spacing: 8) {
            Button(intent: ToggleWorkoutPauseIntent()) {
                control(state.isPaused ? "Resume" : "Pause", systemImage: state.isPaused ? "play.fill" : "pause.fill")
            }
            if state.isCountingRounds {
                Button(intent: CountRoundIntent()) {
                    control("+1 round", systemImage: "plus.circle.fill")
                }
            }
            Button(intent: NextIntervalIntent()) {
                if state.isCountingUp {
                    control("Done", systemImage: "checkmark")
                } else {
                    control("Next", systemImage: "forward.end.fill")
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func control(_ title: LocalizedStringKey, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(fill, in: Capsule())
    }
}

/// Ticks by itself while running; frozen while paused. Counts up on an
/// interval that waits for a tap.
private struct Countdown: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        Group {
            if let shown = state.pausedRemaining {
                Text(state.isCountingUp ? TimeFormat.clock(Int(shown)) : TimeFormat.countdown(shown))
            } else if state.isFinished {
                Text(TimeFormat.countdown(0))
            } else if state.isCountingUp {
                Text(state.phaseStart, style: .timer)
            } else {
                Text(timerInterval: state.phaseStart...max(state.phaseStart, state.phaseEnd), countsDown: true)
            }
        }
        .monospacedDigit()
    }
}

private func kind(_ state: WorkoutActivityAttributes.ContentState) -> PhaseKind {
    PhaseKind(rawValue: state.phaseKind) ?? .work
}

private func phaseColor(_ state: WorkoutActivityAttributes.ContentState) -> Color {
    PhaseStyle.color(for: state.isFinished ? nil : kind(state), pale: false)
}

private func symbol(_ state: WorkoutActivityAttributes.ContentState) -> String {
    state.isPaused ? "pause.fill" : PhaseStyle.symbol(for: kind(state))
}

private func counterText(_ state: WorkoutActivityAttributes.ContentState) -> String {
    var parts: [String] = []
    if state.isCountingRounds {
        parts.append(String(localized: "\(state.roundsCounted ?? 0) rounds", comment: "AMRAP rounds counted so far"))
    }
    if state.roundsTotal > 0 {
        parts.append(String(localized: "Round \(state.round)/\(state.roundsTotal)"))
    }
    if state.cyclesTotal > 1 {
        parts.append(String(localized: "Cycle \(state.cycle)/\(state.cyclesTotal)"))
    }
    return parts.joined(separator: " · ")
}
