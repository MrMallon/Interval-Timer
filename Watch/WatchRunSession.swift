import AVFoundation
import Foundation
import HealthKit
import Observation
import WatchKit

/// A workout running on Apple Watch. Same engine and cue plan as the iPhone;
/// cues are played as wrist taps (with their system sounds) and spoken words.
@Observable
@MainActor
final class WatchRunSession: Identifiable {
    let id = UUID()
    let name: String
    let color: ThemeColor
    let definition: TimerDefinition
    let plan: WorkoutPlan

    private(set) var snapshot: TimerSnapshot
    private(set) var flashCount = 0
    private(set) var startedAt: Date?
    private(set) var endedAt: Date?
    private(set) var endedEarly = false

    @ObservationIgnored private var engine: TimerEngine
    @ObservationIgnored private var cursor: CueCursor
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let speech = AVSpeechSynthesizer()
    @ObservationIgnored private let keepAlive = WorkoutKeepAlive()
    @ObservationIgnored private var loop: Task<Void, Never>?

    init(name: String, color: ThemeColor, definition: TimerDefinition, settings: SettingsStore) {
        self.name = name
        self.color = color
        self.definition = definition
        self.settings = settings
        let plan = WorkoutPlan(name: name, definition: definition)
        self.plan = plan
        let engine = TimerEngine(plan: plan)
        self.engine = engine
        self.cursor = CueCursor(cues: CuePlanner.cues(for: plan, settings: settings.cue))
        self.snapshot = engine.snapshot(at: Self.now())
    }

    private static func now() -> TimeInterval { Date().timeIntervalSinceReferenceDate }

    var isRunning: Bool { snapshot.status == .running }
    var isPaused: Bool { snapshot.status == .paused }
    var isFinished: Bool { snapshot.status == .finished }

    // MARK: - Controls

    func start() {
        guard engine.status == .idle else { return }
        // A workout session keeps the app running with the wrist down.
        keepAlive.begin()
        cursor = CueCursor(cues: CuePlanner.cues(for: plan, settings: settings.cue))
        let now = Self.now()
        startedAt = Date()
        engine.start(at: now)
        process(at: now)
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.process(at: Self.now())
                if self.isFinished { return }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    func togglePause() {
        let now = Self.now()
        engine.togglePause(at: now)
        if engine.status == .running {
            cursor.skip(to: engine.elapsed(at: now))
        }
        process(at: now)
    }

    func skipForward() {
        let now = Self.now()
        engine.skipForward(at: now)
        cursor.jump(to: engine.elapsed(at: now))
        process(at: now, force: true)
    }

    func end() {
        if !isFinished {
            endedEarly = true
            snapshot = engine.snapshot(at: Self.now())
            endedAt = Date()
        }
        teardown()
    }

    func teardown() {
        loop?.cancel()
        loop = nil
        speech.stopSpeaking(at: .immediate)
        keepAlive.end()
    }

    // MARK: - Loop

    private func process(at now: TimeInterval, force: Bool = false) {
        let justFinished = engine.update(at: now)
        let newSnapshot = engine.snapshot(at: now)
        if newSnapshot != snapshot || force {
            snapshot = newSnapshot
        }
        if engine.status == .running || justFinished || force {
            for cue in cursor.advance(to: engine.elapsed(at: now)) {
                perform(cue.event)
            }
        }
        if justFinished {
            endedAt = Date()
            loop?.cancel()
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self?.keepAlive.end()
            }
        }
    }

    private func perform(_ event: CueEvent) {
        let cue = settings.cue
        let taps = cue.beeps || cue.haptics
        let device = WKInterfaceDevice.current()
        switch event {
        case .segmentStart(let index):
            guard plan.segments.indices.contains(index) else { return }
            if cue.flash { flashCount += 1 }
            if taps { device.play(plan.segments[index].kind == .work ? .start : .stop) }
            speakIfEnabled(event)
        case .countdown:
            if taps {
                device.play(.click)
            } else {
                speakIfEnabled(event)
            }
        case .timeRemaining:
            if cue.timeMarkers { speakIfEnabled(event, interrupt: false) }
        case .upNext:
            if cue.announceNext { speakIfEnabled(event, interrupt: false) }
        case .tick:
            if cue.ticking { device.play(.click) }
        case .finished:
            if cue.flash { flashCount += 1 }
            if taps { device.play(.success) }
            speakIfEnabled(event, interrupt: false)
        }
    }

    private func speakIfEnabled(_ event: CueEvent, interrupt: Bool = true) {
        guard settings.cue.voice, let line = VoiceScript.line(for: event, plan: plan) else { return }
        if interrupt, speech.isSpeaking { speech.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: line)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.preferredLanguages.first ?? "en-US")
        speech.speak(utterance)
    }

    // MARK: - Results

    var roundsCompleted: Int {
        let elapsed = snapshot.elapsed
        var count = 0
        for (index, segment) in plan.segments.enumerated() where segment.kind == .work {
            if Double(plan.startOffsets[index] + segment.duration) <= elapsed + 0.001 { count += 1 }
        }
        return count
    }

    var workSecondsDone: Double {
        let elapsed = snapshot.elapsed
        var total: Double = 0
        for (index, segment) in plan.segments.enumerated() where segment.kind == .work {
            let start = Double(plan.startOffsets[index])
            total += max(0, min(start + Double(segment.duration), elapsed) - start)
        }
        return total
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

/// Runs an HKWorkoutSession for the length of a timer so watchOS keeps the
/// app running (and cueing) when the wrist is lowered. Nothing is saved to Health.
final class WorkoutKeepAlive: NSObject, HKWorkoutSessionDelegate, @unchecked Sendable {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var wanted = false

    func begin() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        wanted = true
        let workoutType = HKObjectType.workoutType()
        store.requestAuthorization(toShare: [workoutType], read: []) { [weak self] _, _ in
            DispatchQueue.main.async { self?.startSession() }
        }
    }

    private func startSession() {
        guard wanted, session == nil else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .highIntensityIntervalTraining
        configuration.locationType = .unknown
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            session.delegate = self
            session.startActivity(with: Date())
            self.session = session
        } catch {
            // Without HealthKit the timer still works; it just pauses with the wrist down.
            print("Workout session unavailable: \(error)")
        }
    }

    func end() {
        wanted = false
        session?.end()
        session = nil
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("Workout session failed: \(error)")
    }
}
