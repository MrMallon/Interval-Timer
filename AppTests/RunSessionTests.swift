import AVFoundation
import XCTest
@testable import IntervalTimer

/// Runs real workouts in real time inside the simulator.
@MainActor
final class RunSessionTests: XCTestCase {
    private func makeSession(_ definition: TimerDefinition, cue: CueSettings = CueSettings()) -> RunSession {
        RunSession(name: "Test", color: .red, definition: definition, templateID: nil, settings: makeSettings(cue))
    }

    // MARK: - Phone calls and other interruptions

    func testPhoneCallPausesAndResumesWithoutCountingCallTime() async throws {
        let session = makeSession(simple(work: 60))
        session.start()
        defer { session.teardown() }
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(session.isRunning)

        postAudioInterruption(began: true)
        try await waitUntil(2, "Workout did not pause when the call started") { session.isPaused }
        let pausedAt = session.snapshot.elapsed

        try await Task.sleep(nanoseconds: 1_500_000_000)   // the "call"
        XCTAssertEqual(session.snapshot.elapsed, pausedAt, accuracy: 0.01, "Time moved while paused")

        postAudioInterruption(began: false, shouldResume: true)
        try await waitUntil(2, "Workout did not resume after the call") { session.isRunning }
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(session.snapshot.elapsed, pausedAt + 0.2, accuracy: 0.25, "Call time was counted")
    }

    func testInterruptionWithoutResumeFlagStaysPaused() async throws {
        let session = makeSession(simple(work: 60))
        session.start()
        defer { session.teardown() }

        postAudioInterruption(began: true)
        try await waitUntil(2) { session.isPaused }
        postAudioInterruption(began: false, shouldResume: false)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(session.isPaused, "iOS said not to resume, so we must wait for the user")
    }

    func testCallEndingDoesNotUndoTheUsersOwnPause() async throws {
        let session = makeSession(simple(work: 60))
        session.start()
        defer { session.teardown() }

        session.togglePause()
        XCTAssertTrue(session.isPaused)
        postAudioInterruption(began: true)
        try await Task.sleep(nanoseconds: 200_000_000)
        postAudioInterruption(began: false, shouldResume: true)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(session.isPaused, "A workout the user paused must stay paused after a call")
    }

    // MARK: - Cue timing

    func testCuesPlayOnTimeThroughAWholeWorkout() async throws {
        // 2 s get ready, 3 s work, 2 s rest, 3 s work = 10 s
        let session = makeSession(simple(prepare: 2, work: 3, rest: 2, rounds: 2))
        session.start()
        defer { session.teardown() }

        try await waitUntil(15, "Workout never finished") { session.isFinished }

        let events = session.cueRecords.map(\.event)
        let starts = events.filter { if case .segmentStart = $0 { return true }; return false }
        XCTAssertEqual(starts.count, 4, "Expected a start cue for each of the 4 intervals")
        XCTAssertTrue(events.contains(.countdown(secondsLeft: 2, segmentIndex: 1)))
        XCTAssertTrue(events.contains(.countdown(secondsLeft: 1, segmentIndex: 1)))
        XCTAssertEqual(events.last, .finished)

        let maxLate = session.cueRecords.map(\.lateness).max() ?? 0
        XCTAssertLessThan(maxLate, 0.25, "A cue played \(maxLate) s late")
    }

    func testFinishedWorkoutMakesACompleteHistoryRecord() async throws {
        let session = makeSession(simple(work: 2, rest: 1, rounds: 2), cue: CueSettings(voice: false))
        session.start()
        defer { session.teardown() }
        try await waitUntil(8) { session.isFinished }

        let record = session.makeRecord()
        XCTAssertTrue(record.completed)
        XCTAssertEqual(record.roundsCompleted, 2)
        XCTAssertEqual(record.totalRounds, 2)
        XCTAssertEqual(record.totalSeconds, 5, accuracy: 0.01)
        XCTAssertEqual(record.workSeconds, 4, accuracy: 0.01)
    }

    func testEndingEarlyIsRecordedAsIncomplete() async throws {
        let session = makeSession(simple(work: 30, rounds: 3), cue: CueSettings(voice: false))
        session.start()
        try await Task.sleep(nanoseconds: 1_000_000_000)
        session.end()

        let record = session.makeRecord()
        XCTAssertFalse(record.completed)
        XCTAssertEqual(record.roundsCompleted, 0)
        XCTAssertEqual(record.totalSeconds, 1, accuracy: 0.3)
    }

    func testSkipForwardAnnouncesTheNewInterval() async throws {
        let session = makeSession(simple(prepare: 10, work: 10), cue: CueSettings(voice: false))
        session.start()
        defer { session.teardown() }

        session.skipForward()
        XCTAssertEqual(session.snapshot.segment?.kind, .work)
        XCTAssertEqual(session.cueRecords.last?.event, .segmentStart(index: 1))
    }
}
