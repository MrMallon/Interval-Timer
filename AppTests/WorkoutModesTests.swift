import XCTest
@testable import IntervalTimer

/// "Tap when done" intervals, For Time, AMRAP, repeat groups and the Lock Screen buttons,
/// run for real in the simulator.
@MainActor
final class WorkoutModesTests: XCTestCase {
    private func makeSession(_ definition: TimerDefinition, cue: CueSettings = CueSettings(voice: false)) -> RunSession {
        RunSession(name: "Test", color: .red, definition: definition, templateID: nil, settings: makeSettings(cue))
    }

    // MARK: - Tap when done

    func testTapIntervalWaitsThenDoneMovesOn() async throws {
        let session = makeSession(.custom([
            Segment(kind: .work, duration: 0, label: "20 push-ups", untilTapped: true),
            Segment(kind: .rest, duration: 2)
        ]))
        session.start()
        defer { session.teardown() }

        try await Task.sleep(nanoseconds: 1_200_000_000)
        XCTAssertTrue(session.isWaitingForDone)
        XCTAssertEqual(session.snapshot.segmentIndex, 0, "Must still be on the push-ups")
        XCTAssertGreaterThan(session.snapshot.elapsedInSegment, 1, "The clock counts up")

        session.skipForward()
        XCTAssertFalse(session.isWaitingForDone)
        XCTAssertEqual(session.snapshot.segmentIndex, 1)
        XCTAssertEqual(session.plan.segments[0].duration, 2, "1.2 s taken, kept as 2 s")

        try await waitUntil(5, "The rest after Done never finished") { session.isFinished }
        let starts = session.cueRecords.filter { if case .segmentStart = $0.event { return true }; return false }
        XCTAssertEqual(starts.count, 2, "Rest must be announced once, after Done, not while waiting")
        XCTAssertEqual(session.cueRecords.last?.event, .finished)
    }

    func testForTimeFinishesOnDoneAndSavesTheTime() async throws {
        let session = makeSession(.forTime(ForTimeConfig(prepare: 0, timeCap: 0)))
        session.start()
        defer { session.teardown() }

        try await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertFalse(session.isFinished)
        session.skipForward()
        XCTAssertTrue(session.isFinished)

        let record = session.makeRecord()
        XCTAssertTrue(record.completed)
        XCTAssertEqual(record.totalSeconds, 2, accuracy: 0.01)
        XCTAssertEqual(record.workSeconds, 2, accuracy: 0.01)
    }

    func testForTimeCapEndsTheWorkout() async throws {
        let session = makeSession(.forTime(ForTimeConfig(prepare: 0, timeCap: 2)))
        session.start()
        defer { session.teardown() }
        try await waitUntil(5, "The time cap didn't end the workout") { session.isFinished }
    }

    // MARK: - AMRAP

    func testAmrapCountsRoundsIntoHistory() async throws {
        let session = makeSession(.amrap(AmrapConfig(prepare: 0, work: 2, sets: 1, rest: 0)))
        session.start()
        defer { session.teardown() }

        session.countRound()
        session.countRound()
        session.countRound()
        session.uncountRound()
        XCTAssertEqual(session.roundsCounted, 2)

        try await waitUntil(5, "AMRAP never finished") { session.isFinished }
        session.countRound()
        XCTAssertEqual(session.roundsCounted, 2, "No counting after the clock runs out")

        let record = session.makeRecord()
        XCTAssertEqual(record.roundsCompleted, 2)
        XCTAssertEqual(record.totalRounds, 0, "AMRAP has no target number of rounds")
    }

    func testRoundsOnlyCountDuringAnAmrap() {
        let session = makeSession(simple(work: 30))
        session.start()
        defer { session.teardown() }
        session.countRound()
        XCTAssertEqual(session.roundsCounted, 0)
    }

    // MARK: - Lock Screen buttons

    func testLockScreenButtonsReachTheRunningWorkout() async throws {
        let session = makeSession(simple(work: 30, rest: 10, rounds: 2))
        session.start()
        defer { session.teardown() }

        WorkoutRemote.send(.togglePause)
        XCTAssertTrue(session.isPaused)
        WorkoutRemote.send(.togglePause)
        XCTAssertTrue(session.isRunning)
        WorkoutRemote.send(.next)
        XCTAssertEqual(session.snapshot.segment?.kind, .rest)
    }

    func testLockScreenButtonsGoQuietAfterTheWorkout() {
        let session = makeSession(simple(work: 30))
        session.start()
        session.teardown()
        XCTAssertNil(WorkoutRemote.owner)
        WorkoutRemote.send(.togglePause)   // must not reach the ended workout
        XCTAssertTrue(session.isRunning || session.isFinished)
    }

    func testLiveActivityStateCountsUpOnATapInterval() {
        var engine = TimerEngine(plan: WorkoutPlan(name: "T", definition: .forTime(ForTimeConfig(prepare: 0, timeCap: 0))))
        engine.start(at: 0)
        let now = Date()
        let running = WorkoutActivityAttributes.ContentState.make(
            snapshot: engine.snapshot(at: 75), plan: engine.plan, now: now) { $0.displayName }
        XCTAssertTrue(running.isCountingUp)
        XCTAssertEqual(running.phaseStart.timeIntervalSince(now), -75, accuracy: 0.01)
        XCTAssertGreaterThan(running.phaseEnd.timeIntervalSince(now), 3600, "No end, so no stale countdown")

        engine.pause(at: 80)
        let paused = WorkoutActivityAttributes.ContentState.make(
            snapshot: engine.snapshot(at: 90), plan: engine.plan, now: now) { $0.displayName }
        XCTAssertEqual(paused.pausedRemaining ?? -1, 80, accuracy: 0.01, "Paused shows the time so far")
    }

    func testLiveActivityStateShowsAmrapRounds() {
        var engine = TimerEngine(plan: WorkoutPlan(name: "A", definition: .amrap(AmrapConfig(prepare: 0, work: 600))))
        engine.start(at: 0)
        let state = WorkoutActivityAttributes.ContentState.make(
            snapshot: engine.snapshot(at: 10), plan: engine.plan, now: Date(), roundsCounted: 4) { $0.displayName }
        XCTAssertTrue(state.isCountingRounds)
        XCTAssertEqual(state.roundsCounted, 4)
        XCTAssertEqual(state.roundsTotal, 0, "No plan round counter in an AMRAP")
    }

    // MARK: - Repeat groups and sharing

    func testRepeatGroupRunsShowTheirOwnRoundCounter() {
        let group = RepeatGroup(repeats: 3)
        let session = makeSession(.custom([
            Segment(kind: .prepare, duration: 5),
            Segment(kind: .work, duration: 20, group: group),
            Segment(kind: .rest, duration: 10, group: group)
        ]))
        XCTAssertEqual(session.plan.segments.count, 7)
        XCTAssertEqual(session.plan.totalDuration, 95)
        let lastWork = session.plan.segments[5]
        XCTAssertEqual(session.plan.roundCounter(for: lastWork)?.round, 3)
        XCTAssertEqual(session.plan.roundCounter(for: lastWork)?.total, 3)
    }

    func testNewModesShareThroughAQRCode() throws {
        let group = RepeatGroup(repeats: 4)
        let definitions: [TimerDefinition] = [
            .amrap(AmrapConfig(prepare: 10, work: 720, sets: 2, rest: 60)),
            .forTime(ForTimeConfig(prepare: 10, timeCap: 1200)),
            .custom([
                Segment(kind: .work, duration: 0, label: "Run 400 m", untilTapped: true),
                Segment(kind: .work, duration: 40, label: "Burpees", group: group),
                Segment(kind: .rest, duration: 20, group: group)
            ])
        ]
        for definition in definitions {
            let timer = SharedTimer(name: "WOD", color: .red, definition: definition)
            let link = try XCTUnwrap(timer.link)
            XCTAssertEqual(SharedTimer.from(link: link), timer)
        }
    }

    func testSummariesForNewModes() {
        XCTAssertEqual(TimerSummary.describe(.amrap(AmrapConfig(prepare: 10, work: 720))), "AMRAP 12:00")
        XCTAssertEqual(TimerSummary.describe(.forTime(ForTimeConfig(timeCap: 0))), "For Time")
        XCTAssertEqual(TimerSummary.describe(.forTime(ForTimeConfig(timeCap: 1200))), "For Time · 20:00 cap")
        let open = TimerDefinition.custom([Segment(kind: .work, duration: 30), Segment(kind: .work, duration: 0, untilTapped: true)])
        XCTAssertTrue(TimerSummary.describe(open).hasSuffix("0:30+"))
    }

    func testVoiceUsesTheGroupsRoundCount() {
        let group = RepeatGroup(repeats: 3)
        let plan = WorkoutPlan(name: "G", definition: .custom([
            Segment(kind: .rest, duration: 10),
            Segment(kind: .work, duration: 20, group: group)
        ]))
        XCTAssertEqual(VoiceScript.line(for: .upNext(segmentIndex: 1), plan: plan), "Next: round 1 of 3")
    }
}
