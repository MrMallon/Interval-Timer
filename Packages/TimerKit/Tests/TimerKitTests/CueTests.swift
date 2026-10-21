import XCTest
@testable import TimerKit

final class CueTests: XCTestCase {
    private func events(_ cues: [ScheduledCue], at time: TimeInterval) -> [CueEvent] {
        cues.filter { $0.time == time }.map(\.event)
    }

    func testSegmentStartsCountdownAndFinish() {
        // prepare 10, work 20, rest 10, work 20 → total 60
        let plan = WorkoutPlan(name: "T", definition: .simple(
            SimpleConfig(prepare: 10, work: 20, rest: 10, rounds: 2, cycles: 1, restBetweenCycles: 0, coolDown: 0)
        ))
        let cues = CuePlanner.cues(for: plan, settings: CueSettings(countdownSeconds: 3, timeMarkers: false, announceNext: false))

        XCTAssertEqual(events(cues, at: 0), [.segmentStart(index: 0)])
        XCTAssertEqual(events(cues, at: 7), [.countdown(secondsLeft: 3, segmentIndex: 0)])
        XCTAssertEqual(events(cues, at: 9), [.countdown(secondsLeft: 1, segmentIndex: 0)])
        XCTAssertEqual(events(cues, at: 10), [.segmentStart(index: 1)])
        XCTAssertEqual(events(cues, at: 60), [.finished])
        XCTAssertEqual(cues.filter { if case .segmentStart = $0.event { return true }; return false }.count, 4)
    }

    func testTicksSkipCountdownSeconds() {
        let plan = WorkoutPlan(name: "T", segments: [Segment(kind: .work, duration: 6)])
        let cues = CuePlanner.cues(for: plan, settings: CueSettings(countdownSeconds: 3, timeMarkers: false))
        let tickTimes = cues.filter { if case .tick = $0.event { return true }; return false }.map(\.time)
        XCTAssertEqual(tickTimes, [1, 2])
    }

    func testTimeMarkersOnlyInLongSegments() {
        let plan = WorkoutPlan(name: "T", segments: [
            Segment(kind: .work, duration: 600),
            Segment(kind: .rest, duration: 20)
        ])
        let cues = CuePlanner.cues(for: plan, settings: CueSettings(markerPoints: [300, 60, 30]))
        let markers = cues.compactMap { cue -> Int? in
            if case .timeRemaining(let seconds, _) = cue.event { return seconds }
            return nil
        }
        // 300, 60, 30 fire in the 10-minute work; none fit in the 20 s rest.
        XCTAssertEqual(markers, [300, 60, 30])
        XCTAssertEqual(events(cues, at: 300).first, .timeRemaining(seconds: 300, segmentIndex: 0))
    }

    func testUpNextAnnouncedDuringRest() {
        let plan = WorkoutPlan(name: "T", segments: [
            Segment(kind: .work, duration: 20, round: 1, cycle: 1),
            Segment(kind: .rest, duration: 15, round: 1, cycle: 1),
            Segment(kind: .work, duration: 20, round: 2, cycle: 1)
        ])
        let cues = CuePlanner.cues(for: plan, settings: CueSettings(countdownSeconds: 3, timeMarkers: false))
        // Rest runs 20...35; announce 3 + 4 = 7 s before its end → 28.
        XCTAssertTrue(events(cues, at: 28).contains(.upNext(segmentIndex: 2)))
        // No announcement inside work segments.
        XCTAssertEqual(cues.filter { $0.event == .upNext(segmentIndex: 1) }.count, 0)
    }

    func testShortRestSkipsUpNext() {
        let plan = WorkoutPlan(name: "T", segments: [
            Segment(kind: .work, duration: 20),
            Segment(kind: .rest, duration: 5),
            Segment(kind: .work, duration: 20)
        ])
        let cues = CuePlanner.cues(for: plan, settings: CueSettings(countdownSeconds: 3))
        XCTAssertFalse(cues.contains { if case .upNext = $0.event { return true }; return false })
    }

    func testCursorFiresEachCueOnce() {
        let plan = WorkoutPlan(name: "T", segments: [Segment(kind: .work, duration: 5)])
        var cursor = CueCursor(cues: CuePlanner.cues(for: plan, settings: CueSettings(countdownSeconds: 3)))

        XCTAssertEqual(cursor.advance(to: 0).map(\.event), [.segmentStart(index: 0)])
        XCTAssertEqual(cursor.advance(to: 0.5).map(\.event), [])
        XCTAssertEqual(cursor.advance(to: 1.05).map(\.event), [.tick(segmentIndex: 0)])
        XCTAssertEqual(cursor.advance(to: 1.05).map(\.event), [])
        XCTAssertEqual(cursor.advance(to: 2.02).map(\.event), [.countdown(secondsLeft: 3, segmentIndex: 0)])
    }

    func testCursorDropsStaleCuesAfterSuspension() {
        // Wake up 30 s late: hear only where we are now, not a burst of old beeps.
        let plan = WorkoutPlan(name: "T", definition: .simple(
            SimpleConfig(prepare: 5, work: 10, rest: 5, rounds: 3, cycles: 1, restBetweenCycles: 0, coolDown: 0)
        ))
        var cursor = CueCursor(cues: CuePlanner.cues(for: plan, settings: CueSettings(countdownSeconds: 3, timeMarkers: false)))
        _ = cursor.advance(to: 0)
        // Segments start at 0, 5, 15, 20, 30, 35. Waking at 30.5 we are in the
        // rest that began at 30 (index 4); the old countdowns are dropped.
        let late = cursor.advance(to: 30.5).map(\.event)
        XCTAssertEqual(late, [.segmentStart(index: 4)])

        // A longer stall: wake at 40 inside the last work segment (index 5, from 35).
        var cursor2 = CueCursor(cues: CuePlanner.cues(for: plan, settings: CueSettings(countdownSeconds: 3, timeMarkers: false)))
        _ = cursor2.advance(to: 0)
        let events2 = cursor2.advance(to: 40).map(\.event)
        XCTAssertEqual(events2.first, .segmentStart(index: 5))
        XCTAssertFalse(events2.contains { if case .countdown = $0 { return true }; return false })
    }

    func testCursorJumpReplaysSegmentStartAfterSeek() {
        let plan = WorkoutPlan(name: "T", segments: [
            Segment(kind: .work, duration: 10),
            Segment(kind: .rest, duration: 10)
        ])
        var cursor = CueCursor(cues: CuePlanner.cues(for: plan, settings: CueSettings()))
        _ = cursor.advance(to: 3)
        cursor.jump(to: 10)
        XCTAssertEqual(cursor.advance(to: 10).map(\.event), [.segmentStart(index: 1)])
    }

    func testSilentSettings() {
        XCTAssertTrue(CueSettings(beeps: false, voice: false, ticking: false).isSilent)
        XCTAssertFalse(CueSettings().isSilent)
    }
}
