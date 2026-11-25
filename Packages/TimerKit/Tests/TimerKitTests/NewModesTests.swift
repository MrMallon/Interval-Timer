import XCTest
@testable import TimerKit

final class TapToFinishTests: XCTestCase {
    /// prepare 5, "20 push-ups" (tap when done), rest 10
    private func makePlan() -> WorkoutPlan {
        WorkoutPlan(name: "T", segments: [
            Segment(kind: .prepare, duration: 5),
            Segment(kind: .work, duration: 0, label: "20 push-ups", untilTapped: true),
            Segment(kind: .rest, duration: 10)
        ])
    }

    func testClockHoldsOnTheIntervalUntilDone() {
        var engine = TimerEngine(plan: makePlan())
        engine.start(at: 0)
        XCTAssertEqual(engine.plan.openIndex, 1)

        // Long after the timed part would have ended, still on the push-ups, counting up.
        let snap = engine.snapshot(at: 100)
        XCTAssertEqual(snap.status, .running)
        XCTAssertEqual(snap.segmentIndex, 1)
        XCTAssertEqual(snap.elapsedInSegment, 95, accuracy: 0.001)
        XCTAssertEqual(snap.remainingInSegment, 0)
        XCTAssertEqual(snap.totalRemaining, 10, accuracy: 0.001, "Only the rest after it is still to come")
        XCTAssertFalse(engine.update(at: 100))
    }

    func testDoneKeepsTheTimeTakenAndMovesOn() {
        var engine = TimerEngine(plan: makePlan())
        engine.start(at: 0)
        XCTAssertTrue(engine.completeCurrentSegment(at: 47.3))

        XCTAssertEqual(engine.plan.segments[1].duration, 43, "42.3 s taken, rounded up")
        XCTAssertNil(engine.plan.openIndex)
        let snap = engine.snapshot(at: 47.3)
        XCTAssertEqual(snap.segmentIndex, 2)
        XCTAssertEqual(snap.elapsedInSegment, 0, accuracy: 0.001)
        XCTAssertEqual(snap.remainingInSegment, 10, accuracy: 0.001)

        engine.update(at: 57.4)
        XCTAssertEqual(engine.status, .finished)
    }

    func testSkipForwardIsDoneOnATapInterval() {
        var engine = TimerEngine(plan: makePlan())
        engine.start(at: 0)
        engine.skipForward(at: 20)
        XCTAssertEqual(engine.snapshot(at: 20).segmentIndex, 2)
        XCTAssertEqual(engine.plan.segments[1].duration, 15)
    }

    func testDoneOnlyWorksOnTapIntervals() {
        var engine = TimerEngine(plan: makePlan())
        engine.start(at: 0)
        XCTAssertFalse(engine.completeCurrentSegment(at: 2), "Get ready is timed")
        XCTAssertFalse(engine.extendCurrentSegment(by: 10, at: 30), "+10 means nothing without a time limit")
    }

    func testOpenIntervalAtTheEndFinishesOnDone() {
        var engine = TimerEngine(plan: WorkoutPlan(name: "T", definition: .forTime(ForTimeConfig(prepare: 0, timeCap: 0))))
        engine.start(at: 0)
        XCTAssertFalse(engine.update(at: 600))
        XCTAssertEqual(engine.status, .running)
        engine.completeCurrentSegment(at: 754.2)
        XCTAssertEqual(engine.status, .finished)
        XCTAssertEqual(engine.elapsed(at: 800), 755, accuracy: 0.001)
    }

    func testPauseStopsTheCountUp() {
        var engine = TimerEngine(plan: makePlan())
        engine.start(at: 0)
        engine.pause(at: 30)
        XCTAssertEqual(engine.snapshot(at: 90).elapsedInSegment, 25, accuracy: 0.001)
        engine.resume(at: 90)
        XCTAssertEqual(engine.snapshot(at: 95).elapsedInSegment, 30, accuracy: 0.001)
    }

    func testTimeCapEndsItAutomatically() {
        var engine = TimerEngine(plan: WorkoutPlan(name: "T", definition: .forTime(ForTimeConfig(prepare: 10, timeCap: 60))))
        engine.start(at: 0)
        XCTAssertNil(engine.plan.openIndex, "A capped interval is timed")
        XCTAssertTrue(engine.update(at: 70))
        XCTAssertEqual(engine.status, .finished)
    }

    func testDoneBeforeTheCapRecordsTheRealTime() {
        var engine = TimerEngine(plan: WorkoutPlan(name: "T", definition: .forTime(ForTimeConfig(prepare: 10, timeCap: 600))))
        engine.start(at: 0)
        engine.completeCurrentSegment(at: 250)
        XCTAssertEqual(engine.status, .finished)
        XCTAssertEqual(engine.elapsed(at: 300), 250, accuracy: 0.001)
    }

    func testCuesStopAtTheOpenIntervalAndResumeAfterDone() {
        let settings = CueSettings(countdownSeconds: 3)
        let before = CuePlanner.cues(for: makePlan(), settings: settings)
        XCTAssertEqual(before.last?.event, .segmentStart(index: 1), "Nothing after the push-ups is timed yet")
        XCTAssertFalse(before.contains { $0.event == .finished })

        var engine = TimerEngine(plan: makePlan())
        engine.start(at: 0)
        engine.completeCurrentSegment(at: 30)
        let after = CuePlanner.cues(for: engine.plan, settings: settings)
        XCTAssertTrue(after.contains(ScheduledCue(time: 30, event: .segmentStart(index: 2))))
        XCTAssertTrue(after.contains(ScheduledCue(time: 40, event: .finished)))
    }

    func testResultsCountTheOpenIntervalSoFar() {
        let plan = makePlan()
        XCTAssertEqual(plan.workSeconds(upTo: 35), 30, accuracy: 0.001)
        XCTAssertEqual(plan.workIntervalsDone(upTo: 35), 0)
    }
}

final class RepeatGroupTests: XCTestCase {
    func testGroupsRepeatAndCountTheirOwnRounds() {
        let group = RepeatGroup(repeats: 3)
        let segments = [
            Segment(kind: .prepare, duration: 10),
            Segment(kind: .work, duration: 40, label: "Squats", group: group),
            Segment(kind: .rest, duration: 20, group: group),
            Segment(kind: .work, duration: 60, label: "Plank")
        ]
        let expanded = TimerDefinition.custom(segments).segments()
        XCTAssertEqual(expanded.map(\.displayName),
                       ["Get ready", "Squats", "Rest", "Squats", "Rest", "Squats", "Rest", "Plank"])
        XCTAssertEqual(expanded.map(\.round), [0, 1, 1, 2, 2, 3, 3, 0])
        XCTAssertEqual(Set(expanded.map(\.id)).count, expanded.count, "Each copy needs its own id")

        let plan = WorkoutPlan(name: "G", segments: expanded)
        XCTAssertEqual(plan.totalDuration, 10 + 3 * 60 + 60)
        XCTAssertEqual(plan.roundCounter(for: expanded[3])?.round, 2)
        XCTAssertEqual(plan.roundCounter(for: expanded[3])?.total, 3)
        XCTAssertNil(plan.roundCounter(for: expanded[7]), "Plank isn't in a group")
    }

    func testExpansionIsStable() {
        let group = RepeatGroup(repeats: 2)
        let segments = [Segment(kind: .work, duration: 30, group: group)]
        XCTAssertEqual(TimerDefinition.custom(segments).segments(), TimerDefinition.custom(segments).segments())
    }

    func testTwoGroupsSideBySide() {
        let a = RepeatGroup(repeats: 2)
        let b = RepeatGroup(repeats: 4)
        let segments = [
            Segment(kind: .work, duration: 10, group: a),
            Segment(kind: .work, duration: 5, group: b)
        ]
        let expanded = TimerDefinition.custom(segments).segments()
        XCTAssertEqual(expanded.map(\.duration), [10, 10, 5, 5, 5, 5])
        XCTAssertEqual(expanded.map { $0.roundsTotal ?? -1 }, [2, 2, 4, 4, 4, 4])
    }

    func testCustomTimersWithoutGroupsRunAsBefore() {
        let segments = Preset.pyramid(steps: [20, 30], rest: 10, prepare: 5)
        XCTAssertEqual(TimerDefinition.custom(segments).segments(), segments)
    }
}

final class AmrapTests: XCTestCase {
    func testSetsUseTheCycleCounter() {
        let plan = WorkoutPlan(name: "A", definition: .amrap(AmrapConfig(prepare: 10, work: 300, sets: 3, rest: 60)))
        XCTAssertEqual(plan.segments.map(\.kind), [.prepare, .work, .rest, .work, .rest, .work])
        XCTAssertEqual(plan.totalDuration, 10 + 3 * 300 + 2 * 60)
        XCTAssertEqual(plan.cycleCount, 3)
        XCTAssertEqual(plan.roundsPerCycle, 0, "Round is what the user counts, not a plan counter")
        XCTAssertTrue(plan.countsRounds)
        XCTAssertTrue(plan.segments[1].countsRounds)
        XCTAssertFalse(plan.segments[2].countsRounds)
    }
}

final class SegmentCodingTests: XCTestCase {
    func testOldFilesStillDecode() throws {
        let json = #"{"id":"5EED0000-0000-4000-8000-000000000001","kind":"work","duration":30,"round":1,"cycle":1}"#
        let segment = try JSONDecoder().decode(Segment.self, from: Data(json.utf8))
        XCTAssertEqual(segment.duration, 30)
        XCTAssertFalse(segment.untilTapped)
        XCTAssertFalse(segment.countsRounds)
        XCTAssertNil(segment.group)
    }

    func testUnusedNewFieldsAreNotWritten() throws {
        let json = String(decoding: try JSONEncoder().encode(Segment(kind: .work, duration: 30)), as: UTF8.self)
        XCTAssertFalse(json.contains("tap"))
        XCTAssertFalse(json.contains("amrap"))
        XCTAssertFalse(json.contains("group"))
    }

    func testOnlyForTimeIsForTime() {
        XCTAssertTrue(TimerDefinition.forTime(ForTimeConfig()).isForTime)
        XCTAssertFalse(TimerDefinition.amrap(AmrapConfig()).isForTime)
        XCTAssertFalse(TimerDefinition.simple(SimpleConfig()).isForTime)
    }

    func testNewModesRoundTrip() throws {
        let definitions: [TimerDefinition] = [
            .amrap(AmrapConfig(prepare: 5, work: 600, sets: 2, rest: 30)),
            .forTime(ForTimeConfig(prepare: 10, timeCap: 900)),
            .custom([Segment(kind: .work, duration: 0, untilTapped: true, group: RepeatGroup(repeats: 3))])
        ]
        for definition in definitions {
            let data = try JSONEncoder().encode(definition)
            XCTAssertEqual(try JSONDecoder().decode(TimerDefinition.self, from: data), definition)
        }
    }
}
