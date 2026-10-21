import SwiftData
import SwiftUI
import TimerKit

/// Interval stopwatch: count up with laps. Resetting saves the session to History.
struct StopwatchView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var stopwatch = Stopwatch()
    @State private var startedAt: Date?
    /// Big digits that still follow the user's text size setting.
    @ScaledMetric(relativeTo: .largeTitle) private var digitSize: CGFloat = 76

    private static func now() -> TimeInterval { Date().timeIntervalSinceReferenceDate }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: stopwatch.status != .running)) { _ in
                    let now = Self.now()
                    VStack(spacing: 8) {
                        Text(TimeFormat.stopwatch(stopwatch.elapsed(at: now)))
                            .font(.system(size: digitSize, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        if !stopwatch.lapMarks.isEmpty {
                            Text(String(localized: "Lap \(stopwatch.lapMarks.count + 1)  \(TimeFormat.stopwatch(stopwatch.currentLap(at: now)))"))
                                .font(.title3)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Stopwatch"))
                    .accessibilityValue(Text(Self.spoken(stopwatch.elapsed(at: now))))
                }
                .padding(.top, 32)

                HStack {
                    CircleButton(
                        title: stopwatch.status == .running ? "Lap" : "Reset",
                        style: .secondary,
                        disabled: stopwatch.status == .idle
                    ) {
                        if stopwatch.status == .running {
                            stopwatch.lap(at: Self.now())
                        } else {
                            saveAndReset()
                        }
                    }
                    Spacer()
                    CircleButton(
                        title: stopwatch.status == .running ? "Stop" : "Start",
                        style: stopwatch.status == .running ? .stop : .start,
                        disabled: false
                    ) {
                        if stopwatch.status == .running {
                            stopwatch.pause(at: Self.now())
                        } else {
                            if stopwatch.status == .idle { startedAt = Date() }
                            stopwatch.start(at: Self.now())
                        }
                    }
                }
                .padding(.horizontal, 32)

                List {
                    ForEach(Array(stopwatch.laps.enumerated()).reversed(), id: \.offset) { index, lap in
                        LabeledContent(String(localized: "Lap \(index + 1)"), value: TimeFormat.stopwatch(lap))
                            .monospacedDigit()
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Stopwatch")
        }
    }

    /// "1 minute, 23 seconds" for VoiceOver instead of "1:23.45".
    static func spoken(_ seconds: TimeInterval) -> String {
        Duration.seconds(Int(seconds)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }

    private func saveAndReset() {
        let now = Self.now()
        let total = stopwatch.elapsed(at: now)
        if total >= 1 {
            var laps = stopwatch.laps
            let tail = stopwatch.currentLap(at: now)
            if tail > 0.01 { laps.append(tail) }
            let record = WorkoutRecord(
                name: String(localized: "Stopwatch"),
                kind: .stopwatch,
                color: .teal,
                startedAt: startedAt ?? Date().addingTimeInterval(-total),
                endedAt: Date(),
                totalSeconds: total,
                completed: true,
                laps: laps
            )
            modelContext.insert(record)
            SyncCoordinator.shared.send(record)
        }
        stopwatch.reset()
        startedAt = nil
    }
}

private struct CircleButton: View {
    enum Style {
        case start, stop, secondary

        /// Solid fills chosen so the label passes WCAG AA contrast.
        var fill: Color {
            switch self {
            case .start: return PhaseStyle.color(for: .rest, pale: false)
            case .stop: return PhaseStyle.color(for: .work, pale: false)
            case .secondary: return Color(.systemGray5)
            }
        }

        var text: Color { self == .secondary ? .primary : .white }
    }

    let title: LocalizedStringKey
    let style: Style
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 10)
                .frame(width: 92, height: 92)
                .foregroundStyle(style.text)
                .background(style.fill, in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}
