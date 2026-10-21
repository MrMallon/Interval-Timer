import XCTest
@testable import TimerKit

final class SimpleConfigTests: XCTestCase {
    func testTabataExpansion() {
        let config = SimpleConfig(prepare: 10, work: 20, rest: 10, rounds: 8, cycles: 1, restBetweenCycles: 0, coolDown: 0)
        let segments = config.segments()

        // prepare + 8 work + 7 rests (no rest after the final round)
        XCTAssertEqual(segments.count, 1 + 8 + 7)
        XCTAssertEqual(segments.first?.kind, .prepare)
        XCTAssertEqual(segments.last?.kind, .work)
        XCTAssertEqual(segments.filter { $0.kind == .work }.count, 8)
        XCTAssertEqual(config.totalDuration, 10 + 8 * 20 + 7 * 10)
    }

    func testCyclesUseRestBetweenCycles() {
        let config = SimpleConfig(prepare: 0, work: 30, rest: 10, rounds: 3, cycles: 2, restBetweenCycles: 60, coolDown: 0)
        let kinds = config.segments().map(\.kind)
        XCTAssertEqual(kinds, [.work, .rest, .work, .rest, .work, .cycleRest,
                               .work, .rest, .work, .rest, .work])
    }

    func testCycleFallsBackToNormalRestWhenNoCycleRest() {
        let config = SimpleConfig(prepare: 0, work: 30, rest: 10, rounds: 2, cycles: 2, restBetweenCycles: 0, coolDown: 0)
        let kinds = config.segments().map(\.kind)
        XCTAssertEqual(kinds, [.work, .rest, .work, .rest, .work, .rest, .work])
    }

    func testRoundAndCycleNumbering() {
        let config = SimpleConfig(prepare: 5, work: 30, rest: 10, rounds: 2, cycles: 2, restBetweenCycles: 20, coolDown: 30)
        let work = config.segments().filter { $0.kind == .work }
        XCTAssertEqual(work.map(\.round), [1, 2, 1, 2])
        XCTAssertEqual(work.map(\.cycle), [1, 1, 2, 2])
        XCTAssertEqual(config.segments().last?.kind, .coolDown)
    }

    func testZeroRestProducesBackToBackWork() {
        let config = SimpleConfig(prepare: 0, work: 60, rest: 0, rounds: 3, cycles: 1, restBetweenCycles: 0, coolDown: 0)
        XCTAssertEqual(config.segments().map(\.kind), [.work, .work, .work])
    }

    func testInputsAreClamped() {
        let config = SimpleConfig(prepare: -5, work: 0, rest: -1, rounds: 0, cycles: -2, restBetweenCycles: -1, coolDown: -1)
        XCTAssertEqual(config.prepare, 0)
        XCTAssertEqual(config.work, 1)
        XCTAssertEqual(config.rounds, 1)
        XCTAssertEqual(config.cycles, 1)
        XCTAssertEqual(config.segments().count, 1)
    }

    func testDefinitionRoundTripsThroughCodable() throws {
        let definitions: [TimerDefinition] = [
            .simple(SimpleConfig()),
            .custom(Preset.pyramid(steps: [10, 20], rest: 5, prepare: 3))
        ]
        for definition in definitions {
            let data = try JSONEncoder().encode(definition)
            let decoded = try JSONDecoder().decode(TimerDefinition.self, from: data)
            XCTAssertEqual(decoded, definition)
        }
    }

    func testPyramidPreset() {
        let segments = Preset.pyramid(steps: [20, 30, 20], rest: 15, prepare: 10)
        XCTAssertEqual(segments.map(\.duration), [10, 20, 15, 30, 15, 20])
        XCTAssertEqual(segments.filter { $0.kind == .work }.map(\.round), [1, 2, 3])
    }

    func testAllPresetsAreRunnable() {
        for preset in Preset.all {
            let plan = WorkoutPlan(name: preset.name, definition: preset.definition)
            XCTAssertFalse(plan.isEmpty, preset.id)
            XCTAssertGreaterThan(plan.totalDuration, 0, preset.id)
        }
    }
}
