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
    /// Changes when the user adds time to an interval or taps Done.
    private(set) var plan: WorkoutPlan

    private(set) var snapshot: TimerSnapshot
    private(set) var flashCount = 0
    private(set) var startedAt: Date?
    private(set) var endedAt: Date?
    private(set) var endedEarly = false
    /// AMRAP: rounds the user has tapped in.
    private(set) var roundsCounted = 0
    /// Latest heart rate in beats per minute, when "Show heart rate" is on.
    private(set) var heartRate: Int?
    private(set) var maxHeartRate: Int?
    @ObservationIgnored private var heartRateSum = 0.0
    @ObservationIgnored private var heartRateCount = 0

    @ObservationIgnored private var engine: TimerEngine
    @ObservationIgnored private var cursor: CueCursor
    @ObservationIgnored private let settings: SettingsStore
    @ObservationIgnored private let speech = AVSpeechSynthesizer()
    @ObservationIgnored private lazy var voice = SpeechVoices.voice(identifier: settings.cue.voiceIdentifier)
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
        keepAlive.onHeartRate = { [weak self] readings in
            Task { @MainActor in self?.addHeartRates(readings) }
        }
        keepAlive.begin(saveToHealth: settings.saveToHealth, readHeartRate: settings.showHeartRate)
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

    /// Next interval. On an interval that waits for a tap, this is Done.
    func skipForward() {
        let now = Self.now()
        engine.skipForward(at: now)
        if engine.plan != plan {
            plan = engine.plan
            cursor = CueCursor(cues: CuePlanner.cues(for: plan, settings: settings.cue))
        }
        cursor.jump(to: engine.elapsed(at: now))
        process(at: now, force: true)
    }

    /// True while the interval running now waits for the user to tap Done.
    var isWaitingForDone: Bool { snapshot.segment?.untilTapped ?? false }

    /// AMRAP: one more round finished.
    func countRound() {
        guard snapshot.segment?.countsRounds == true, !isFinished else { return }
        roundsCounted += 1
        if settings.cue.haptics { WKInterfaceDevice.current().play(.click) }
    }

    func uncountRound() {
        roundsCounted = max(0, roundsCounted - 1)
    }

    /// Average heart rate over the workout so far.
    var averageHeartRate: Int? {
        heartRateCount > 0 ? Int((heartRateSum / Double(heartRateCount)).rounded()) : nil
    }

    /// Readings, oldest first, in beats per minute.
    private func addHeartRates(_ readings: [Double]) {
        guard !readings.isEmpty, !isFinished else { return }
        for bpm in readings where bpm > 0 {
            heartRateSum += bpm
            heartRateCount += 1
            maxHeartRate = max(maxHeartRate ?? 0, Int(bpm.rounded()))
        }
        if let latest = readings.last { heartRate = Int(latest.rounded()) }
    }

    /// "+10 s": lengthens the interval running now.
    func addTime(_ seconds: Int) {
        let now = Self.now()
        guard engine.extendCurrentSegment(by: seconds, at: now) else { return }
        plan = engine.plan
        cursor = CueCursor(cues: CuePlanner.cues(for: plan, settings: settings.cue))
        cursor.skip(to: engine.elapsed(at: now))
        if settings.cue.haptics { WKInterfaceDevice.current().play(.click) }
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
        keepAlive.end(save: shouldSaveToHealth)
    }

    /// Workouts shorter than 30 s aren't worth a Health entry.
    private var shouldSaveToHealth: Bool {
        settings.saveToHealth && snapshot.elapsed >= 30
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
                guard let self else { return }
                self.keepAlive.end(save: self.shouldSaveToHealth)
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
        utterance.voice = voice
        speech.speak(utterance)
    }

    // MARK: - Results

    /// Work intervals fully completed, or the rounds counted in an AMRAP.
    var roundsCompleted: Int {
        plan.countsRounds ? roundsCounted : plan.workIntervalsDone(upTo: snapshot.elapsed)
    }

    var workSecondsDone: Double { plan.workSeconds(upTo: snapshot.elapsed) }

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
            totalRounds: plan.countsRounds ? 0 : plan.workCount,
            completed: !endedEarly && isFinished,
            definition: definition
        )
    }
}

/// Runs an HKWorkoutSession for the length of a timer so watchOS keeps the
/// app running (and cueing) when the wrist is lowered. When "Save to Apple
/// Health" is on, the session's workout (with heart rate and calories) is saved
/// at the end; otherwise nothing is written to Health.
final class WorkoutKeepAlive: NSObject, HKWorkoutSessionDelegate, @unchecked Sendable {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var heartRateQuery: HKAnchoredObjectQuery?
    private var collecting = false
    private var wanted = false
    private var record = false
    private var readHeartRate = false
    /// New heart rate readings (beats per minute, oldest first), on a background queue.
    var onHeartRate: (@Sendable ([Double]) -> Void)?

    /// `readHeartRate` asks to read heart rate (only when the user turned on
    /// "Show heart rate"); nothing else is ever read.
    func begin(saveToHealth: Bool, readHeartRate: Bool = false) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        wanted = true
        record = saveToHealth
        self.readHeartRate = readHeartRate
        var share: Set<HKSampleType> = [HKObjectType.workoutType()]
        if saveToHealth {
            share.insert(HKQuantityType(.activeEnergyBurned))
            share.insert(HKQuantityType(.heartRate))
        }
        let read: Set<HKObjectType> = readHeartRate ? [HKQuantityType(.heartRate)] : []
        store.requestAuthorization(toShare: share, read: read) { [weak self] _, _ in
            DispatchQueue.main.async { self?.startSession() }
        }
    }

    /// Streams heart rate measured from `start` on. The running workout session
    /// makes the watch measure every few seconds.
    private func startHeartRateQuery(from start: Date) {
        let type = HKQuantityType(.heartRate)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: .strictStartDate)
        let handler: (HKAnchoredObjectQuery, [HKSample]?, [HKDeletedObject]?, HKQueryAnchor?, Error?) -> Void = { [weak self] _, samples, _, _, _ in
            let perMinute = HKUnit.count().unitDivided(by: .minute())
            let readings = (samples as? [HKQuantitySample] ?? [])
                .sorted { $0.endDate < $1.endDate }
                .map { $0.quantity.doubleValue(for: perMinute) }
            guard !readings.isEmpty else { return }
            self?.onHeartRate?(readings)
        }
        let query = HKAnchoredObjectQuery(type: type, predicate: predicate, anchor: nil, limit: HKObjectQueryNoLimit, resultsHandler: handler)
        query.updateHandler = handler
        heartRateQuery = query
        store.execute(query)
    }

    private func startSession() {
        guard wanted, session == nil else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .highIntensityIntervalTraining
        configuration.locationType = .unknown
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            session.delegate = self
            let start = Date()
            session.startActivity(with: start)
            self.session = session
            if readHeartRate { startHeartRateQuery(from: start) }
            if record, store.authorizationStatus(for: .workoutType()) == .sharingAuthorized {
                let builder = session.associatedWorkoutBuilder()
                builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
                self.builder = builder
                builder.beginCollection(withStart: start) { [weak self] began, _ in
                    DispatchQueue.main.async { self?.collecting = began }
                }
            }
        } catch {
            // Without HealthKit the timer still works; it just pauses with the wrist down.
            print("Workout session unavailable: \(error)")
        }
    }

    /// Ends the session. `save` keeps the workout in Health (only if recording was on).
    func end(save: Bool = false) {
        wanted = false
        if let heartRateQuery {
            store.stop(heartRateQuery)
            self.heartRateQuery = nil
        }
        guard let session else { return }
        self.session = nil
        session.end()
        guard let builder else { return }
        self.builder = nil
        if save, collecting {
            builder.endCollection(withEnd: Date()) { _, _ in
                builder.finishWorkout { _, error in
                    if let error { print("Saving to Health failed: \(error)") }
                }
            }
        } else {
            builder.discardWorkout()
        }
        collecting = false
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("Workout session failed: \(error)")
    }
}
