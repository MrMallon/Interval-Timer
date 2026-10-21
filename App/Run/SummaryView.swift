import SwiftUI
import TimerKit

/// Shown when a workout finishes or is ended early.
struct SummaryView: View {
    let session: RunSession
    let onDone: () -> Void
    let onRepeat: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var completed: Bool { session.isFinished && !session.endedEarly }

    var body: some View {
        // Scrolls at very large text sizes instead of clipping.
        ScrollView {
            content
                .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var content: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 40)
            Image(systemName: completed ? "checkmark.seal.fill" : "flag.checkered")
                .font(.system(size: 72))
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(completed ? "Workout complete" : "Workout ended")
                    .font(.largeTitle.bold())
                    .accessibilityIdentifier("summaryTitle")
                Text(session.name)
                    .font(.title3)
            }
            .multilineTextAlignment(.center)

            // Side by side normally; stacked when the user picks an accessibility text size.
            let tiles = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 10))
                : AnyLayout(HStackLayout(spacing: 14))
            tiles {
                StatTile(title: "Total", value: TimeFormat.clock(Int(session.snapshot.elapsed.rounded())))
                StatTile(title: "Working", value: TimeFormat.clock(Int(session.workSecondsDone.rounded())))
                StatTile(title: "Rounds", value: "\(session.roundsCompleted)/\(session.plan.workCount)")
            }
            .padding(.horizontal)

            Spacer(minLength: 24)

            VStack(spacing: 12) {
                Button(action: onRepeat) {
                    Label("Do it again", systemImage: "arrow.counterclockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(PhaseStyle.controlFill, in: RoundedRectangle(cornerRadius: 16))
                }
                .accessibilityIdentifier("repeatButton")
                Button(action: onDone) {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .foregroundStyle(.black)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                }
                .accessibilityIdentifier("doneButton")
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
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(PhaseStyle.controlFill, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}
