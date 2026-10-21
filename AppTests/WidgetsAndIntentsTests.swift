import XCTest
@testable import IntervalTimer

final class DeepLinkTests: XCTestCase {
    func testStartLinkRoundTrips() {
        let id = UUID()
        let link = DeepLink.start(id)
        XCTAssertEqual(link.url.absoluteString, "intervaltimer://start/\(id.uuidString)")
        XCTAssertEqual(DeepLink(url: link.url), link)
    }

    func testRejectsOtherLinks() {
        XCTAssertNil(DeepLink(url: URL(string: "intervaltimer://start/not-a-uuid")!))
        XCTAssertNil(DeepLink(url: URL(string: "intervaltimer://open/\(UUID().uuidString)")!))
        XCTAssertNil(DeepLink(url: URL(string: "https://example.com/start/\(UUID().uuidString)")!))
    }

    func testWidgetStoreRoundTrips() {
        let timers = [WidgetTimer(id: UUID(), name: "Legs", colorName: "red", summary: "8 × 0:20 · 4:00")]
        WidgetStore.save(timers)
        XCTAssertEqual(WidgetStore.load(), timers)
    }
}

final class LiveActivityStateTests: XCTestCase {
    /// get ready 5 s, then work 20 / rest 10 × 2 rounds, 2 cycles with 30 s between
    private let plan = WorkoutPlan(name: "T", definition: .simple(
        SimpleConfig(prepare: 5, work: 20, rest: 10, rounds: 2, cycles: 2, restBetweenCycles: 30, coolDown: 0)
    ))

    func testRunningStateCarriesPhaseEndForTheSelfTickingCountdown() {
        var engine = TimerEngine(plan: plan)
        engine.start(at: 0)
        let now = Date(timeIntervalSince1970: 1_000)
        let state = WorkoutActivityAttributes.ContentState.make(
            snapshot: engine.snapshot(at: 12), plan: plan, now: now
        ) { $0.kind.rawValue }

        XCTAssertEqual(state.phaseKind, PhaseKind.work.rawValue)
        XCTAssertEqual(state.phaseName, "work")
        XCTAssertEqual(state.round, 1)
        XCTAssertEqual(state.roundsTotal, 2)
        XCTAssertEqual(state.cyclesTotal, 2)
        XCTAssertEqual(state.phaseEnd.timeIntervalSince(now), 13, accuracy: 0.001)   // work runs 5...25
        XCTAssertEqual(now.timeIntervalSince(state.phaseStart), 7, accuracy: 0.001)
        XCTAssertNil(state.pausedRemaining)
        XCTAssertEqual(state.nextName, "rest")
        XCTAssertFalse(state.isFinished)
    }

    func testPausedStateFreezesRemainingTime() {
        var engine = TimerEngine(plan: plan)
        engine.start(at: 0)
        engine.pause(at: 8)
        let state = WorkoutActivityAttributes.ContentState.make(
            snapshot: engine.snapshot(at: 500), plan: plan, now: Date()
        ) { $0.kind.rawValue }
        XCTAssertEqual(state.pausedRemaining ?? -1, 17, accuracy: 0.001)
        XCTAssertTrue(state.isPaused)
    }

    func testFinishedState() {
        var engine = TimerEngine(plan: plan)
        engine.start(at: 0)
        engine.update(at: 10_000)
        let state = WorkoutActivityAttributes.ContentState.make(
            snapshot: engine.snapshot(at: 10_000), plan: plan, now: Date()
        ) { $0.kind.rawValue }
        XCTAssertTrue(state.isFinished)
        XCTAssertNil(state.nextName)
    }
}

@MainActor
final class IntentTests: XCTestCase {
    func testStartTimerIntentRoutesToTheTimer() async throws {
        let id = UUID()
        AppRouter.shared.selectedTab = .settings
        _ = try await StartTimerIntent(timer: TimerEntity(id: id, name: "Legs")).perform()
        XCTAssertEqual(AppRouter.shared.pendingStart, id)
        XCTAssertEqual(AppRouter.shared.selectedTab, .timers)
        AppRouter.shared.pendingStart = nil
    }

    func testDeepLinkRoutesToTheTimer() {
        let id = UUID()
        AppRouter.shared.handle(DeepLink.start(id).url)
        XCTAssertEqual(AppRouter.shared.pendingStart, id)
        AppRouter.shared.pendingStart = nil
    }

    func testSiriCanFindSavedTimersByName() async throws {
        let context = AppPersistence.container.mainContext
        let template = TimerTemplate(name: "Kettlebell EMOM", definition: simple(work: 60, rounds: 10))
        context.insert(template)
        try context.save()
        defer { context.delete(template); try? context.save() }

        let query = TimerEntityQuery()
        let matches = try await query.entities(matching: "kettlebell")
        XCTAssertEqual(matches.map(\.id), [template.id])
        let byID = try await query.entities(for: [template.id])
        XCTAssertEqual(byID.first?.name, "Kettlebell EMOM")
        let suggested = try await query.suggestedEntities()
        XCTAssertTrue(suggested.contains { $0.id == template.id })
    }
}
