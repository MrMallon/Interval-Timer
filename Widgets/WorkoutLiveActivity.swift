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
                    HStack {
                        Text(context.attributes.timerName)
                            .lineLimit(1)
                        Spacer()
                        Text(counterText(state))
                            .monospacedDigit()
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
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
        .foregroundStyle(.white)
        .padding(16)
    }
}

/// Ticks by itself while running; frozen while paused.
private struct Countdown: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        Group {
            if let remaining = state.pausedRemaining {
                Text(TimeFormat.countdown(remaining))
            } else if state.isFinished {
                Text(TimeFormat.countdown(0))
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
    if state.roundsTotal > 0 {
        parts.append(String(localized: "Round \(state.round)/\(state.roundsTotal)"))
    }
    if state.cyclesTotal > 1 {
        parts.append(String(localized: "Cycle \(state.cycle)/\(state.cyclesTotal)"))
    }
    return parts.joined(separator: " · ")
}
