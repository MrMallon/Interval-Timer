import SwiftData
import XCTest
@testable import IntervalTimer

@MainActor
final class PersistenceTests: XCTestCase {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: TimerTemplate.self, WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    func testEditingASavedTimerUpdatesItInPlace() throws {
        let context = try makeContext()
        let template = TimerTemplate(name: "Legs", definition: simple(work: 30, rest: 10, rounds: 8))
        context.insert(template)
        try context.save()
        let id = template.id

        template.name = "Legs v2"
        template.definition = simple(work: 45, rest: 15, rounds: 6)
        try context.save()

        let all = try context.fetch(FetchDescriptor<TimerTemplate>())
        XCTAssertEqual(all.count, 1, "Editing must not create a copy")
        XCTAssertEqual(all.first?.id, id)
        XCTAssertEqual(all.first?.name, "Legs v2")
        guard case .simple(let config) = all.first?.definition else { return XCTFail("Wrong definition") }
        XCTAssertEqual(config.work, 45)
        XCTAssertEqual(config.rounds, 6)
    }

    func testHistoryKeepsTheTimerAsItWasRun() throws {
        let context = try makeContext()
        let template = TimerTemplate(name: "Tabata", definition: simple(work: 20, rest: 10, rounds: 8))
        context.insert(template)
        let record = WorkoutRecord(
            name: template.name, kind: .interval, color: .red,
            startedAt: Date(), endedAt: Date(), totalSeconds: 230,
            completed: true, definition: template.definition
        )
        context.insert(record)

        template.definition = simple(work: 40, rounds: 2)
        try context.save()

        guard case .simple(let snapshot) = record.definition else { return XCTFail("Missing snapshot") }
        XCTAssertEqual(snapshot.work, 20, "History must not change when the timer is edited later")
    }

    func testCustomTimerRoundTrips() throws {
        let context = try makeContext()
        let segments = Preset.pyramid(steps: [20, 30, 20], rest: 10, prepare: 5)
        let template = TimerTemplate(name: "Pyramid", definition: .custom(segments))
        context.insert(template)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TimerTemplate>()).first
        XCTAssertEqual(fetched?.definition, .custom(segments))
    }

    func testStopwatchLapsAreStored() {
        let record = WorkoutRecord(
            name: "Stopwatch", kind: .stopwatch, color: .teal,
            startedAt: Date(), endedAt: Date(), totalSeconds: 25,
            completed: true, laps: [10, 15]
        )
        XCTAssertEqual(record.laps, [10, 15])
        XCTAssertEqual(record.kind, .stopwatch)
    }
}

final class VoiceScriptTests: XCTestCase {
    private let tabata = WorkoutPlan(name: "Tabata", definition: simple(prepare: 10, work: 20, rest: 10, rounds: 8))

    func testAnnouncesUpcomingRound() {
        // Index 0 = get ready, 1 = round 1 work, 2 = rest, 3 = round 2 work.
        XCTAssertEqual(VoiceScript.line(for: .upNext(segmentIndex: 3), plan: tabata), "Next: round 2 of 8")
    }

    func testAnnouncesCycleAtTheStartOfANewCycle() {
        let plan = WorkoutPlan(name: "C", definition: .simple(
            SimpleConfig(prepare: 0, work: 30, rest: 10, rounds: 2, cycles: 3, restBetweenCycles: 60, coolDown: 0)
        ))
        // work, rest, work, cycleRest, work(cycle 2, round 1)
        XCTAssertEqual(VoiceScript.line(for: .upNext(segmentIndex: 4), plan: plan), "Next: cycle 2 of 3, round 1 of 2")
    }

    func testTimeLeftMarkers() {
        XCTAssertEqual(VoiceScript.line(for: .timeRemaining(seconds: 300, segmentIndex: 0), plan: tabata), "5 minutes left")
        XCTAssertEqual(VoiceScript.line(for: .timeRemaining(seconds: 60, segmentIndex: 0), plan: tabata), "1 minute left")
        XCTAssertEqual(VoiceScript.line(for: .timeRemaining(seconds: 30, segmentIndex: 0), plan: tabata), "30 seconds left")
    }

    func testCountdownAndPhaseNames() {
        XCTAssertEqual(VoiceScript.line(for: .countdown(secondsLeft: 3, segmentIndex: 1), plan: tabata), "3")
        XCTAssertEqual(VoiceScript.line(for: .segmentStart(index: 0), plan: tabata), "Get ready")
        XCTAssertEqual(VoiceScript.line(for: .segmentStart(index: 1), plan: tabata), "Work")
        XCTAssertNil(VoiceScript.line(for: .tick(segmentIndex: 1), plan: tabata))
    }

    func testCustomEditorNumbersRounds() {
        let segments = [
            Segment(kind: .prepare, duration: 5),
            Segment(kind: .work, duration: 20),
            Segment(kind: .rest, duration: 10),
            Segment(kind: .work, duration: 30)
        ]
        let numbered = TimerEditorView.renumbered(segments)
        XCTAssertEqual(numbered.map(\.round), [0, 1, 1, 2])
    }
}
