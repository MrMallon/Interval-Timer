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
    /// 0...1 while the end button is held down.
    @State private var endHoldProgress = 0.0

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
        .foregroundStyle(PhaseStyle.foreground(pale: settings.paleColors))
        .preferredColorScheme(settings.paleColors ? .light : .dark)
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
            Button("End workout", role: .destructive) { endNow() }
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
            // Anywhere that isn't a button: tap to pause or resume, swipe to skip.
            // Big targets for sweaty hands; the buttons below stay for VoiceOver.
            .contentShape(Rectangle())
            .onTapGesture { session.togglePause() }
            .gesture(
                DragGesture(minimumDistance: 40)
                    .onEnded { value in
                        let dx = value.translation.width
                        guard abs(dx) > abs(value.translation.height) * 1.5 else { return }
                        if dx < 0 { session.skipForward() } else { session.skipBackward() }
                    }
            )
        }
    }

    private var topBar: some View {
        HStack {
            endButton
                .frame(width: 60, alignment: .leading)

            Spacer()
            VStack(spacing: 2) {
                Text(session.name)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if session.isPaused {
                    Text("Paused")
                        .font(.subheadline.weight(.heavy))
                        .textCase(.uppercase)
                        .accessibilityIdentifier("pausedLabel")
                } else {
                    Text(String(localized: "\(TimeFormat.countdown(snapshot.totalRemaining)) left"))
                        .font(.subheadline.monospacedDigit())
                }
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Button {
                session.addTime(10)
            } label: {
                Text(verbatim: "+10")
                    .font(.headline.monospacedDigit())
                    .frame(minWidth: 44, minHeight: 44)
                    .padding(.horizontal, 6)
                    .background(PhaseStyle.controlFill, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(session.isFinished)
            .accessibilityLabel("Add 10 seconds")
            .accessibilityIdentifier("addTimeButton")
            .frame(width: 60, alignment: .trailing)
        }
        .padding(.top, 8)
    }

    /// Tap: asks first. Touch and hold: ends straight away, with a ring filling up.
    private var endButton: some View {
        Image(systemName: "xmark")
            .font(.title3.bold())
            .frame(width: 44, height: 44)
            .background(PhaseStyle.controlFill, in: Circle())
            .overlay {
                Circle()
                    .trim(from: 0, to: endHoldProgress)
                    .stroke(.foreground, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(2)
            }
            .contentShape(Circle())
            .onTapGesture {
                if session.isFinished { close() } else { confirmEnd = true }
            }
            .onLongPressGesture(minimumDuration: 0.8) {
                endHoldProgress = 0
                if session.isFinished { close() } else { endNow() }
            } onPressingChanged: { pressing in
                if pressing {
                    withAnimation(.linear(duration: 0.8)) { endHoldProgress = 1 }
                } else {
                    withAnimation(.easeOut(duration: 0.15)) { endHoldProgress = 0 }
                }
            }
            .accessibilityElement()
            .accessibilityLabel("End workout")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if session.isFinished { close() } else { confirmEnd = true }
            }
            .accessibilityIdentifier("endButton")
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

    /// "Next: …" while running; how to resume while paused. One text that changes,
    /// so pausing doesn't add or remove anything on screen.
    @ViewBuilder
    private var nextUp: some View {
        if let line = nextUpLine {
            Text(line)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.top, 4)
                .accessibilityIdentifier(session.isPaused ? "pausedHint" : "nextUp")
        }
    }

    private var nextUpLine: String? {
        if session.isPaused {
            return String(localized: "Tap to resume")
        }
        if let next = snapshot.nextSegment {
            return String(localized: "Next: \(PhaseStyle.name(for: next)) · \(TimeFormat.clock(next.duration))")
        }
        return snapshot.segment != nil ? String(localized: "Last interval") : nil
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
        return phase + ", " + String(localized: "\(seconds) seconds remaining")
    }

    // MARK: - Actions

    private func flash() {
        flashOpacity = 0.85
        withAnimation(.easeOut(duration: 0.45)) {
            flashOpacity = 0
        }
    }

    private func endNow() {
        session.end()
        finishAndShowSummary()
    }

    private func finishAndShowSummary() {
        saveRecordIfNeeded()
        withAnimation { showSummary = true }
    }

    private func saveRecordIfNeeded() {
        guard !recordSaved, session.snapshot.elapsed >= 1 else { return }
        recordSaved = true
        let record = session.makeRecord()
        modelContext.insert(record)
        try? modelContext.save()
        SyncCoordinator.shared.send(record)
        AppPersistence.refreshExternalViews()
        if settings.saveToHealth { HealthLogger.save(record) }
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
            Text(value)
                .fontWeight(.bold)
                .monospacedDigit()
        }
        .font(.title3)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(PhaseStyle.controlFill, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

private struct SegmentProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(PhaseStyle.controlFill)
                Capsule()
                    .fill(.foreground)
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
                .background(PhaseStyle.controlFill, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier(identifier)
    }
}
