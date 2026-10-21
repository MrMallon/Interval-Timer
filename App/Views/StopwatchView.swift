import SwiftData
import SwiftUI
import TimerKit

/// Interval stopwatch: count up with laps. Resetting saves the session to History.
struct StopwatchView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var stopwatch = Stopwatch()
    @State private var startedAt: Date?

    private static func now() -> TimeInterval { Date().timeIntervalSinceReferenceDate }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: stopwatch.status != .running)) { _ in
                    let now = Self.now()
                    VStack(spacing: 8) {
                        Text(TimeFormat.stopwatch(stopwatch.elapsed(at: now)))
                            .font(.system(size: 76, weight: .semibold, design: .rounded))
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
                    .accessibilityElement(children: .combine)
                }
                .padding(.top, 32)

                HStack {
                    CircleButton(
                        title: stopwatch.status == .running ? "Lap" : "Reset",
                        tint: .gray,
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
                        tint: stopwatch.status == .running ? .red : .green,
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
    let title: LocalizedStringKey
    let tint: Color
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.title3.weight(.semibold))
                .frame(width: 92, height: 92)
                .foregroundStyle(tint)
                .background(tint.opacity(0.18), in: Circle())
                .overlay(Circle().stroke(tint.opacity(0.4), lineWidth: 2).padding(4))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
}
