import SwiftUI
import TimerKit

/// Shown when a workout finishes or is ended early.
struct SummaryView: View {
    let session: RunSession
    let onDone: () -> Void
    let onRepeat: () -> Void

    private var completed: Bool { session.isFinished && !session.endedEarly }

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: completed ? "checkmark.seal.fill" : "flag.checkered")
                .font(.system(size: 72))
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(completed ? "Workout complete" : "Workout ended")
                    .font(.largeTitle.bold())
                Text(session.name)
                    .font(.title3)
                    .opacity(0.85)
            }
            .multilineTextAlignment(.center)

            HStack(spacing: 14) {
                StatTile(title: "Total", value: TimeFormat.clock(Int(session.snapshot.elapsed.rounded())))
                StatTile(title: "Working", value: TimeFormat.clock(Int(session.workSecondsDone.rounded())))
                StatTile(title: "Rounds", value: "\(session.roundsCompleted)/\(session.plan.workCount)")
            }
            .padding(.horizontal)

            Spacer()

            VStack(spacing: 12) {
                Button(action: onRepeat) {
                    Label("Do it again", systemImage: "arrow.counterclockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.white.opacity(0.22), in: RoundedRectangle(cornerRadius: 16))
                }
                Button(action: onDone) {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(.black)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}

private struct StatTile: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.subheadline)
                .opacity(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}
