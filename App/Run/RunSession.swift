import Foundation
import Observation
import SwiftUI
import TimerKit
import UIKit

/// One workout in progress. Owns the engine, the cue cursor and the audio.
@Observable
@MainActor
final class RunSession: Identifiable {
    let id = UUID()
    let name: String
    let color: ThemeColor
    let definition: TimerDefinition
    let plan: WorkoutPlan
    let templateID: UUID?

    private(set) var snapshot: TimerSnapshot
    /// Incremented on every phase change; the run screen flashes when it changes.
    private(set) var flashCount = 0
    private(set) var startedAt: Date?
    private(set) var endedAt: Date?
    private(set) var endedEarly = false
    /// One-line cue report shown (invisibly) to UI tests.
    private(set) var debugSummary = "starts=0 countdowns=0 bg=0 maxLate=0.00 audio=0"

    struct CueRecord: Equatable {
        let event: CueEvent
        /// When the cue was due, in seconds from workout start.
        let scheduledAt: TimeInterval
        /// When it actually played, in seconds from workout start.
        let firedAt: TimeInterval
        let inBackground: Bool
        var lateness: TimeInterval { firedAt - scheduledAt }
    }

    /// Every cue that has played, in order.
    @ObservationIgnored private(set) var cueRecords: [CueRecord] = []

    @ObservationIgnored private var engine: TimerEngine
    @ObservationIgnored private var cursor: CueCursor
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let audio = AudioCuePlayer()
    @ObservationIgnored private let haptics = Haptics()
    @ObservationIgnored private let liveActivity = LiveActivityController()
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var pausedByInterruption = false

    init(name: String, color: ThemeColor, definition: TimerDefinition, templateID: UUID?, settings: SettingsStore) {
        self.name = name
        self.color = color
        self.definition = definition
        self.templateID = templateID
        self.settings = settings
        let plan = WorkoutPlan(name: name, definition: definition)
        self.plan = plan
        let engine = TimerEngine(plan: plan)
        self.engine = engine
        self.cursor = CueCursor(cues: CuePlanner.cues(for: plan, settings: settings.cue))
        self.snapshot = engine.snapshot(at: Self.now())
    }

    private static func now() -> TimeInterval {
        Date().timeIntervalSinceReferenceDate
    }

    var status: TimerEngine.Status { snapshot.status }
    var isRunning: Bool { status == .running }
    var isPaused: Bool { status == .paused }
    var isFinished: Bool { status == .finished }

    // MARK: - Controls

    func start() {
        guard engine.status == .idle else { return }
        audio.onInterruption = { [weak self] began, shouldResume in
            self?.handleInterruption(began: began, shouldResume: shouldResume)
        }
        audio.activate(settings: settings.cue)
        cursor = CueCursor(cues: CuePlanner.cues(for: plan, settings: settings.cue))
        if settings.cue.isSilent {
            NotificationFallback.requestAuthorizationIfNeeded()
        }
        let now = Self.now()
        startedAt = Date()
        engine.start(at: now)
        haptics.prepare()
        process(at: now)
        liveActivity.start(name: name, color: color, state: activityState())
        startLoop()
        updateIdleTimer()
    }

    func togglePause() {
        let now = Self.now()
        pausedByInterruption = false
        engine.togglePause(at: now)
        if engine.status == .running {
            // Don't replay anything that "happened" while paused.
            cursor.skip(to: engine.elapsed(at: now))
        }
        process(at: now)
        updateIdleTimer()
    }

    func skipForward() {
        let now = Self.now()
        engine.skipForward(at: now)
        cursor.jump(to: engine.elapsed(at: now))
        process(at: now, force: true)
    }

    func skipBackward() {
        let now = Self.now()
        engine.skipBackward(at: now)
        cursor.jump(to: engine.elapsed(at: now))
        process(at: now, force: true)
    }

    /// Ends the workout early.
    func end() {
        guard !isFinished else {
            teardown()
            return
        }
        endedEarly = true
        let now = Self.now()
        snapshot = engine.snapshot(at: now)
        endedAt = Date()
        teardown()
    }

    /// Call when leaving the run screen for good.
    func teardown() {
        loop?.cancel()
        loop = nil
        liveActivity.end(nil, finished: false)
        audio.deactivate()
        NotificationFallback.cancelAll()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - App lifecycle

    func sceneDidBecomeActive() {
        NotificationFallback.cancelAll()
        process(at: Self.now())
    }

    func sceneDidEnterBackground() {
        // With sound on, background audio keeps us running. With every sound
        // off we leave audio alone, so local notifications mark phase changes.
        guard settings.cue.isSilent, engine.status == .running else { return }
        NotificationFallback.schedule(plan: plan, elapsed: engine.elapsed(at: Self.now()))
    }

    // MARK: - Loop

    private func startLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.process(at: Self.now())
                if self.isFinished { return }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }

    private func process(at now: TimeInterval, force: Bool = false) {
        let justFinished = engine.update(at: now)
        let newSnapshot = engine.snapshot(at: now)
        if newSnapshot != snapshot || force {
            snapshot = newSnapshot
        }
        if engine.status == .running || justFinished || force {
            let elapsedNow = engine.elapsed(at: now)
            let due = cursor.advance(to: elapsedNow)
            for cue in due {
                perform(cue.event)
                record(cue, firedAt: elapsedNow)
            }
        }
        if liveActivity.isActive {
            if justFinished {
                liveActivity.end(activityState(), finished: true)
            } else {
                liveActivity.update(activityState())
            }
        }
        if justFinished {
            endedAt = Date()
            loop?.cancel()
            UIApplication.shared.isIdleTimerDisabled = false
            // Let the finish sound play out, then release audio.
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 3_500_000_000)
                self?.audio.deactivate()
            }
        }
    }

    private func perform(_ event: CueEvent) {
        let cue = settings.cue
        switch event {
        case .segmentStart(let index):
            guard plan.segments.indices.contains(index) else { return }
            let segment = plan.segments[index]
            if cue.flash { flashCount += 1 }
            if cue.haptics { haptics.phaseChange() }
            if cue.beeps { audio.play(tone: segment.kind == .work ? .go : .restStart) }
            if cue.voice, let line = VoiceScript.line(for: event, plan: plan) { audio.speak(line) }

        case .countdown:
            if cue.haptics { haptics.tick() }
            if cue.beeps {
                audio.play(tone: .countdown)
            } else if cue.voice, let line = VoiceScript.line(for: event, plan: plan) {
                audio.speak(line)
            }

        case .timeRemaining:
            if cue.voice, cue.timeMarkers, let line = VoiceScript.line(for: event, plan: plan) {
                audio.speak(line, interrupt: false)
            }

        case .upNext:
            if cue.voice, cue.announceNext, let line = VoiceScript.line(for: event, plan: plan) {
                audio.speak(line, interrupt: false)
            }

        case .tick:
            if cue.ticking { audio.play(tone: .tick) }

        case .finished:
            if cue.flash { flashCount += 1 }
            if cue.haptics { haptics.finished() }
            if cue.beeps { audio.play(tones: ToneSynth.Tone.finished) }
            if cue.voice, let line = VoiceScript.line(for: event, plan: plan) { audio.speak(line, interrupt: false) }
        }
    }

    /// What the Lock Screen / Dynamic Island should show right now.
    private func activityState() -> WorkoutActivityAttributes.ContentState {
        .make(snapshot: snapshot, plan: plan, now: Date()) { PhaseStyle.name(for: $0) }
    }

    /// True while the Live Activity is showing, for tests.
    var isLiveActivityActive: Bool { liveActivity.isActive }

    private func record(_ cue: ScheduledCue, firedAt: TimeInterval) {
        let background = UIApplication.shared.applicationState == .background
        cueRecords.append(CueRecord(event: cue.event, scheduledAt: cue.time, firedAt: firedAt, inBackground: background))
        if LaunchEnvironment.isUITesting {
            debugSummary = Self.summarize(cueRecords, audioRunning: audio.isEngineRunning)
                + " la=\(liveActivity.isActive ? 1 : 0)"
                + " laEnd=\(String(format: "%.1f", liveActivity.systemSecondsToPhaseEnd ?? -99))"
                + " laPhase=\(liveActivity.systemPhaseName ?? "-")"
                + " appRemain=\(String(format: "%.1f", snapshot.remainingInSegment))"
        }
    }

    static func summarize(_ records: [CueRecord], audioRunning: Bool) -> String {
        let starts = records.filter { if case .segmentStart = $0.event { return true }; return false }.count
        let countdowns = records.filter { if case .countdown = $0.event { return true }; return false }.count
        let background = records.filter(\.inBackground).count
        let maxLate = records.map(\.lateness).max() ?? 0
        return "starts=\(starts) countdowns=\(countdowns) bg=\(background) maxLate=\(String(format: "%.2f", maxLate)) audio=\(audioRunning ? 1 : 0)"
    }

    /// Audio state, for tests.
    var isAudioSessionActive: Bool { audio.isSessionActive }
    var isAudioEngineRunning: Bool { audio.isEngineRunning }

    private func handleInterruption(began: Bool, shouldResume: Bool) {
        let now = Self.now()
        if began {
            if engine.status == .running {
                engine.pause(at: now)
                pausedByInterruption = true
                process(at: now)
            }
        } else if pausedByInterruption, shouldResume {
            pausedByInterruption = false
            engine.resume(at: now)
            cursor.skip(to: engine.elapsed(at: now))
            process(at: now)
        }
        updateIdleTimer()
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = settings.keepScreenAwake && engine.status == .running
    }

    // MARK: - Results

    /// Seconds of work actually completed.
    var workSecondsDone: Double {
        let elapsed = snapshot.elapsed
        var total: Double = 0
        for (index, segment) in plan.segments.enumerated() where segment.kind == .work {
            let start = Double(plan.startOffsets[index])
            let end = start + Double(segment.duration)
            total += max(0, min(end, elapsed) - start)
        }
        return total
    }

    /// Work segments fully completed.
    var roundsCompleted: Int {
        let elapsed = snapshot.elapsed
        var count = 0
        for (index, segment) in plan.segments.enumerated() where segment.kind == .work {
            if Double(plan.startOffsets[index] + segment.duration) <= elapsed + 0.001 { count += 1 }
        }
        return count
    }

    func makeRecord() -> WorkoutRecord {
        WorkoutRecord(
            name: name,
            kind: .interval,
            color: color,
            startedAt: startedAt ?? Date(),
            endedAt: endedAt ?? Date(),
            totalSeconds: snapshot.elapsed,
            workSeconds: workSecondsDone,
            roundsCompleted: roundsCompleted,
            totalRounds: plan.workCount,
            completed: !endedEarly && isFinished,
            definition: definition
        )
    }
}

/// Thin wrapper over UIKit feedback generators.
@MainActor
final class Haptics {
    private let impact = UIImpactFeedbackGenerator(style: .heavy)
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let notification = UINotificationFeedbackGenerator()

    func prepare() {
        impact.prepare()
        light.prepare()
    }

    func phaseChange() { impact.impactOccurred() }
    func tick() { light.impactOccurred() }
    func finished() { notification.notificationOccurred(.success) }
}
