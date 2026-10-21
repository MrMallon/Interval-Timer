import SwiftData
import SwiftUI
import TimerKit

/// Full-screen workout: big colour-coded countdown, round/cycle counters and controls.
struct RunView: View {
    @State private var session: RunSession

    @Environment(SettingsStore.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var flashOpacity = 0.0
    @State private var confirmEnd = false
    @State private var showSummary = false
    @State private var recordSaved = false

    init(session: RunSession) {
        _session = State(initialValue: session)
    }

    private var snapshot: TimerSnapshot { session.snapshot }

    var body: some View {
        ZStack {
            PhaseStyle.color(for: showSummary ? nil : snapshot.segment?.kind ?? session.plan.segments.first?.kind,
                             pale: settings.paleColors)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.35), value: snapshot.segmentIndex)

            if showSummary {
                SummaryView(session: session, onDone: close, onRepeat: repeatWorkout)
                    .transition(.opacity)
            } else {
                runContent
            }

            Color.white
                .opacity(flashOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            if LaunchEnvironment.isUITesting {
                // Invisible cue report the UI tests read back.
                Text(session.debugSummary)
                    .font(.system(size: 2))
                    .opacity(0.02)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("cueLog")
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .statusBarHidden(!showSummary)
        .persistentSystemOverlays(.hidden)
        .onAppear { session.start() }
        .onDisappear { session.teardown() }
        .onChange(of: session.flashCount) { _, _ in flash() }
        .onChange(of: session.isFinished) { _, finished in
            if finished { finishAndShowSummary() }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: session.sceneDidBecomeActive()
            case .background: session.sceneDidEnterBackground()
            default: break
            }
        }
        .confirmationDialog("End this workout?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End workout", role: .destructive) {
                session.end()
                finishAndShowSummary()
            }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Your progress so far is saved to History.")
        }
    }

    // MARK: - Run screen

    private var runContent: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let isLandscape = size.width > size.height
            let digitSize = min(size.width * (isLandscape ? 0.28 : 0.30), size.height * 0.36)

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 8)

                VStack(spacing: isLandscape ? 4 : 12) {
                    phaseHeader
                    Text(TimeFormat.countdown(snapshot.remainingInSegment))
                        .font(.system(size: digitSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)
                        .contentTransition(.numericText(countsDown: true))
                        .accessibilityLabel(countdownAccessibilityLabel)
                        .accessibilityIdentifier("countdown")
                    counters
                    SegmentProgressBar(progress: snapshot.segmentProgress)
                        .frame(height: 8)
                        .padding(.horizontal, 32)
                    nextUp
                }

                Spacer(minLength: 8)
                controls
                    .padding(.bottom, isLandscape ? 8 : 24)
            }
            .padding(.horizontal, 20)
            .frame(width: size.width, height: size.height)
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                if session.isFinished { close() } else { confirmEnd = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.title3.bold())
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .accessibilityLabel("End workout")
            .accessibilityIdentifier("endButton")

            Spacer()
            VStack(spacing: 2) {
                Text(session.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(String(localized: "\(TimeFormat.countdown(snapshot.totalRemaining)) left"))
                    .font(.subheadline.monospacedDigit())
                    .opacity(0.85)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.top, 8)
    }

    private var phaseHeader: some View {
        HStack(spacing: 10) {
            if let segment = snapshot.segment {
                Image(systemName: PhaseStyle.symbol(for: segment.kind))
                    .accessibilityHidden(true)
                Text(PhaseStyle.name(for: segment))
            } else {
                Text("Ready")
            }
        }
        .font(.system(.largeTitle, design: .rounded).weight(.heavy))
        .textCase(.uppercase)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("phaseName")
    }

    @ViewBuilder
    private var counters: some View {
        let plan = session.plan
        HStack(spacing: 12) {
            if plan.roundsPerCycle > 0 {
                CounterChip(
                    title: "Round",
                    value: "\(max(1, snapshot.segment?.round ?? 1))/\(plan.roundsPerCycle)"
                )
                .accessibilityIdentifier("roundCounter")
            }
            if plan.cycleCount > 1 {
                CounterChip(
                    title: "Cycle",
                    value: "\(max(1, snapshot.segment?.cycle ?? 1))/\(plan.cycleCount)"
                )
                .accessibilityIdentifier("cycleCounter")
            }
        }
    }

    @ViewBuilder
    private var nextUp: some View {
        if let next = snapshot.nextSegment {
            Text(String(localized: "Next: \(PhaseStyle.name(for: next)) · \(TimeFormat.clock(next.duration))"))
                .font(.title3.weight(.semibold))
                .opacity(0.9)
                .padding(.top, 4)
        } else if snapshot.segment != nil {
            Text("Last interval")
                .font(.title3.weight(.semibold))
                .opacity(0.9)
                .padding(.top, 4)
        }
    }

    private var controls: some View {
        HStack(spacing: 36) {
            ControlButton(systemImage: "backward.end.fill", size: 64, label: "Previous interval", identifier: "previousButton") {
                session.skipBackward()
            }
            ControlButton(
                systemImage: session.isPaused ? "play.fill" : "pause.fill",
                size: 96,
                label: session.isPaused ? "Resume" : "Pause",
                identifier: "pauseButton"
            ) {
                session.togglePause()
            }
            ControlButton(systemImage: "forward.end.fill", size: 64, label: "Next interval", identifier: "nextButton") {
                session.skipForward()
            }
        }
    }

    private var countdownAccessibilityLabel: String {
        let seconds = Int(snapshot.remainingInSegment.rounded(.up))
        let phase = snapshot.segment.map { PhaseStyle.name(for: $0) } ?? ""
        return String(localized: "\(phase), \(seconds) seconds remaining")
    }

    // MARK: - Actions

    private func flash() {
        flashOpacity = 0.85
        withAnimation(.easeOut(duration: 0.45)) {
            flashOpacity = 0
        }
    }

    private func finishAndShowSummary() {
        saveRecordIfNeeded()
        withAnimation { showSummary = true }
    }

    private func saveRecordIfNeeded() {
        guard !recordSaved, session.snapshot.elapsed >= 1 else { return }
        recordSaved = true
        modelContext.insert(session.makeRecord())
    }

    private func close() {
        session.teardown()
        dismiss()
    }

    private func repeatWorkout() {
        session.teardown()
        let next = RunSession(
            name: session.name,
            color: session.color,
            definition: session.definition,
            templateID: session.templateID,
            settings: settings
        )
        recordSaved = false
        session = next
        withAnimation { showSummary = false }
        next.start()
    }
}

// MARK: - Pieces

private struct CounterChip: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .opacity(0.8)
            Text(value)
                .fontWeight(.bold)
                .monospacedDigit()
        }
        .font(.title3)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.white.opacity(0.18), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

private struct SegmentProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.25))
                Capsule()
                    .fill(.white)
                    .frame(width: proxy.size.width * max(0, min(1, progress)))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct ControlButton: View {
    let systemImage: String
    let size: CGFloat
    let label: LocalizedStringKey
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.38, weight: .bold))
                .frame(width: size, height: size)
                .background(.white.opacity(0.2), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier(identifier)
    }
}
