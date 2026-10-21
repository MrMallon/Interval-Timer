import SwiftData
import SwiftUI

struct WatchRunView: View {
    @State private var session: WatchRunSession

    @Environment(SettingsStore.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var flashOpacity = 0.0
    @State private var showSummary = false
    @State private var recordSaved = false
    @State private var confirmEnd = false

    init(session: WatchRunSession) {
        _session = State(initialValue: session)
    }

    private var snapshot: TimerSnapshot { session.snapshot }

    var body: some View {
        ZStack {
            PhaseStyle.color(for: showSummary ? nil : snapshot.segment?.kind ?? session.plan.segments.first?.kind,
                             pale: settings.paleColors)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.3), value: snapshot.segmentIndex)

            if showSummary {
                summary
            } else {
                running
            }

            Color.white
                .opacity(flashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .foregroundStyle(PhaseStyle.foreground(pale: settings.paleColors))
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { session.start() }
        .onDisappear { session.teardown() }
        .onChange(of: session.flashCount) { _, _ in
            flashOpacity = 0.8
            withAnimation(.easeOut(duration: 0.4)) { flashOpacity = 0 }
        }
        .onChange(of: session.isFinished) { _, finished in
            if finished { finish() }
        }
        .confirmationDialog("End workout?", isPresented: $confirmEnd) {
            Button("End", role: .destructive) {
                session.end()
                finish()
            }
            Button("Keep going", role: .cancel) {}
        }
    }

    private var running: some View {
        VStack(spacing: 2) {
            Text(snapshot.segment.map { PhaseStyle.name(for: $0) } ?? String(localized: "Ready"))
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .textCase(.uppercase)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(TimeFormat.countdown(snapshot.remainingInSegment))
                .font(.system(size: 54, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .contentTransition(.numericText(countsDown: true))
                .accessibilityLabel(String(localized: "\(Int(snapshot.remainingInSegment.rounded(.up))) seconds remaining"))

            Text(counterText)
                .font(.footnote.weight(.semibold))
                .monospacedDigit()

            HStack(spacing: 10) {
                RoundButton(systemImage: "xmark", label: "End workout") { confirmEnd = true }
                RoundButton(systemImage: session.isPaused ? "play.fill" : "pause.fill",
                            label: session.isPaused ? "Resume" : "Pause", large: true) {
                    session.togglePause()
                }
                RoundButton(systemImage: "forward.end.fill", label: "Next interval") { session.skipForward() }
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 4)
    }

    private var counterText: String {
        var parts: [String] = []
        let plan = session.plan
        if plan.roundsPerCycle > 0 {
            parts.append(String(localized: "Round \(max(1, snapshot.segment?.round ?? 1))/\(plan.roundsPerCycle)"))
        }
        if plan.cycleCount > 1 {
            parts.append(String(localized: "Cycle \(max(1, snapshot.segment?.cycle ?? 1))/\(plan.cycleCount)"))
        }
        return parts.joined(separator: " · ")
    }

    private var summary: some View {
        ScrollView {
            VStack(spacing: 8) {
                Image(systemName: session.endedEarly ? "flag.checkered" : "checkmark.seal.fill")
                    .font(.title)
                Text(session.endedEarly ? "Workout ended" : "Workout complete")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                LabeledContent("Total", value: TimeFormat.clock(Int(snapshot.elapsed.rounded())))
                LabeledContent("Rounds", value: "\(session.roundsCompleted)/\(session.plan.workCount)")
                Button("Done") {
                    session.teardown()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(PhaseStyle.controlFill)
            }
            .monospacedDigit()
        }
    }

    private func finish() {
        if !recordSaved, snapshot.elapsed >= 1 {
            recordSaved = true
            let record = session.makeRecord()
            modelContext.insert(record)
            try? modelContext.save()
            SyncCoordinator.shared.send(record)
        }
        withAnimation { showSummary = true }
    }
}

private struct RoundButton: View {
    let systemImage: String
    let label: LocalizedStringKey
    var large = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: large ? 22 : 16, weight: .bold))
                .frame(width: large ? 52 : 40, height: large ? 52 : 40)
                .background(PhaseStyle.controlFill, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}
