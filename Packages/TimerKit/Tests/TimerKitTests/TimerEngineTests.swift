import XCTest
@testable import TimerKit

final class TimerEngineTests: XCTestCase {
    /// prepare 5, then work 10 / rest 5 × 2 rounds → 5 + 10 + 5 + 10 = 30 s
    private func makePlan() -> WorkoutPlan {
        WorkoutPlan(name: "Test", definition: .simple(
            SimpleConfig(prepare: 5, work: 10, rest: 5, rounds: 2, cycles: 1, restBetweenCycles: 0, coolDown: 0)
        ))
    }

    func testPlanOffsets() {
        let plan = makePlan()
        XCTAssertEqual(plan.startOffsets, [0, 5, 15, 20])
        XCTAssertEqual(plan.totalDuration, 30)
        XCTAssertEqual(plan.roundsPerCycle, 2)
        XCTAssertEqual(plan.cycleCount, 1)
        XCTAssertEqual(plan.segmentIndex(at: 0), 0)
        XCTAssertEqual(plan.segmentIndex(at: 4.99), 0)
        XCTAssertEqual(plan.segmentIndex(at: 5), 1)
        XCTAssertEqual(plan.segmentIndex(at: 29.9), 3)
        XCTAssertNil(plan.segmentIndex(at: 30))
    }

    func testRunsFromTheClockNotTicks() {
        var engine = TimerEngine(plan: makePlan())
        engine.start(at: 1000)

        let snap = engine.snapshot(at: 1007.5)
        XCTAssertEqual(snap.status, .running)
        XCTAssertEqual(snap.segmentIndex, 1)
        XCTAssertEqual(snap.segment?.kind, .work)
        XCTAssertEqual(snap.elapsedInSegment, 2.5, accuracy: 0.0001)
        XCTAssertEqual(snap.remainingInSegment, 7.5, accuracy: 0.0001)
        XCTAssertEqual(snap.totalRemaining, 22.5, accuracy: 0.0001)
        XCTAssertEqual(snap.nextSegment?.kind, .rest)
    }

    func testPauseExcludesPausedTime() {
        var engine = TimerEngine(plan: makePlan())
        engine.start(at: 0)
        engine.pause(at: 6)
        XCTAssertEqual(engine.status, .paused)
        // An hour passes while paused.
        XCTAssertEqual(engine.elapsed(at: 3606), 6, accuracy: 0.0001)
        engine.resume(at: 3606)
        XCTAssertEqual(engine.elapsed(at: 3610), 10, accuracy: 0.0001)
    }

    func testFinishesExactlyOnce() {
        var engine = TimerEngine(plan: makePlan())
        engine.start(at: 0)
        XCTAssertFalse(engine.update(at: 29.9))
        XCTAssertTrue(engine.update(at: 31))
        XCTAssertFalse(engine.update(at: 40))
        XCTAssertEqual(engine.status, .finished)
        XCTAssertEqual(engine.elapsed(at: 100), 30, accuracy: 0.0001)
        XCTAssertTrue(engine.snapshot(at: 100).isFinished)
        XCTAssertNil(engine.snapshot(at: 100).segment)
    }

    func testSnapshotReportsFinishedEvenBeforeUpdate() {
        var engine = TimerEngine(plan: makePlan())
        engine.start(at: 0)
        XCTAssertEqual(engine.snapshot(at: 45).status, .finished)
    }

    func testSkipForwardGoesToNextSegmentStart() {
        var engine = TimerEngine(plan: makePlan())
        engine.start(at: 0)
        engine.skipForward(at: 7)          // in work #1 → rest at 15
        XCTAssertEqual(engine.elapsed(at: 7), 15, accuracy: 0.0001)
        XCTAssertEqual(engine.snapshot(at: 8).segment?.kind, .rest)
        XCTAssertEqual(engine.elapsed(at: 8), 16, accuracy: 0.0001)
    }

    func testSkipForwardFromLastSegmentFinishes() {
        var engine = TimerEngine(plan: makePlan())
        engine.start(at: 0)
        engine.seek(to: 25, at: 0)
        engine.skipForward(at: 0)
        XCTAssertEqual(engine.status, .finished)
    }

    func testSkipBackwardRestartsThenGoesBack() {
        var engine = TimerEngine(plan: makePlan())
        engine.start(at: 0)
        engine.skipBackward(at: 10)        // 5 s into work → restart work at 5
        XCTAssertEqual(engine.elapsed(at: 10), 5, accuracy: 0.0001)
        engine.skipBackward(at: 11)        // 1 s in → previous (prepare at 0)
        XCTAssertEqual(engine.elapsed(at: 11), 0, accuracy: 0.0001)
    }

    func testSkipWhilePausedStaysPaused() {
        var engine = TimerEngine(plan: makePlan())
        engine.start(at: 0)
        engine.pause(at: 2)
        engine.skipForward(at: 50)
        XCTAssertEqual(engine.status, .paused)
        XCTAssertEqual(engine.elapsed(at: 500), 5, accuracy: 0.0001)
    }

    func testEmptyPlanFinishesImmediately() {
        var engine = TimerEngine(plan: WorkoutPlan(name: "Empty", segments: []))
        engine.start(at: 0)
        XCTAssertEqual(engine.status, .finished)
    }

    func testResetReturnsToIdle() {
        var engine = TimerEngine(plan: makePlan())
        engine.start(at: 0)
        engine.reset()
        XCTAssertEqual(engine.status, .idle)
        XCTAssertEqual(engine.elapsed(at: 99), 0)
    }

    func testStopwatchLaps() {
        var stopwatch = Stopwatch()
        stopwatch.start(at: 100)
        stopwatch.lap(at: 110)
        stopwatch.pause(at: 115)
        stopwatch.start(at: 200)          // 100 s paused
        stopwatch.lap(at: 212)
        XCTAssertEqual(stopwatch.laps, [10, 17])
        XCTAssertEqual(stopwatch.elapsed(at: 220), 35, accuracy: 0.0001)
        XCTAssertEqual(stopwatch.currentLap(at: 220), 8, accuracy: 0.0001)
        stopwatch.reset()
        XCTAssertEqual(stopwatch.status, .idle)
        XCTAssertTrue(stopwatch.laps.isEmpty)
    }

    func testTimeFormatting() {
        XCTAssertEqual(TimeFormat.countdown(2.1), "0:03")
        XCTAssertEqual(TimeFormat.countdown(0), "0:00")
        XCTAssertEqual(TimeFormat.clock(65), "1:05")
        XCTAssertEqual(TimeFormat.clock(3723), "1:02:03")
        XCTAssertEqual(TimeFormat.stopwatch(83.456), "1:23.45")
    }
}
