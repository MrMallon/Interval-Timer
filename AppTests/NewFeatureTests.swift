import XCTest
@testable import IntervalTimer

/// Sharing, repeat-last links, saved-settings upgrades and "+10 s".
@MainActor
final class NewFeatureTests: XCTestCase {
    // MARK: - Sharing

    func testSharedTimerSurvivesALinkRoundTrip() throws {
        let timer = SharedTimer(name: "Legs & core", color: .green, definition: simple(prepare: 10, work: 40, rest: 20, rounds: 8))
        let link = try XCTUnwrap(timer.link)
        XCTAssertEqual(link.scheme, "intervaltimer")
        XCTAssertEqual(link.host, "import")
        XCTAssertEqual(SharedTimer.from(link: link), timer)
    }

    func testCustomTimerFitsInAQRCode() throws {
        let segments = (1...20).map { Segment(kind: $0.isMultiple(of: 2) ? .rest : .work, duration: 30, label: "Move \($0)") }
        let timer = SharedTimer(name: "Circuit", color: .blue, definition: .custom(segments))
        let link = try XCTUnwrap(timer.link, "A 20-interval timer should still fit in a QR code")
        XCTAssertNotNil(QRCode.image(for: link.absoluteString))
        XCTAssertEqual(SharedTimer.from(link: link), timer)
    }

    func testSharedTimerFileRoundTrip() throws {
        let timer = SharedTimer(name: "Tabata", color: .red, definition: simple(work: 20, rest: 10, rounds: 8))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).intervaltimer")
        try timer.fileData().write(to: url)
        XCTAssertEqual(SharedTimer.from(fileURL: url), timer)
    }

    func testBadSharesAreIgnored() {
        XCTAssertNil(SharedTimer.decode(Data("not json".utf8)))
        XCTAssertNil(SharedTimer.from(link: URL(string: "intervaltimer://import?t=garbage")!))
        // A file from a future app version with a format this one doesn't know.
        XCTAssertNil(SharedTimer.decode(Data(#"{"v":2,"name":"X","color":"red","definition":{}}"#.utf8)))
        // A timer with no time in it.
        let empty = SharedTimer(name: "Empty", color: .red, definition: .custom([]))
        XCTAssertNil(SharedTimer.decode(try! empty.fileData()))
    }

    func testOpeningASharedLinkOpensItForSaving() throws {
        let router = AppRouter.shared
        router.pendingImport = nil
        let timer = SharedTimer(name: "Shared", color: .orange, definition: simple(work: 30, rounds: 3))
        router.handle(try XCTUnwrap(timer.link))
        XCTAssertEqual(router.pendingImport, timer)
        XCTAssertEqual(router.selectedTab, .timers)
        router.pendingImport = nil
    }

    // MARK: - Repeat last workout

    func testRepeatLinkRoundTrips() {
        XCTAssertEqual(DeepLink.repeatLast.url.absoluteString, "intervaltimer://repeat")
        XCTAssertEqual(DeepLink(url: DeepLink.repeatLast.url), .repeatLast)
        let id = UUID()
        XCTAssertEqual(DeepLink(url: DeepLink.start(id).url), .start(id))
    }

    func testRepeatLinkAsksLibraryToRunLastWorkout() {
        let router = AppRouter.shared
        router.pendingRepeat = false
        router.handle(DeepLink.repeatLast.url)
        XCTAssertTrue(router.pendingRepeat)
        router.pendingRepeat = false
    }

    // MARK: - Settings

    func testSettingsSavedByVersionOneStillLoad() throws {
        let defaults = UserDefaults(suiteName: "tests-\(UUID().uuidString)")!
        // Exactly what the first release wrote: no voice, beep style or Health keys.
        let old = #"{"cue":{"beeps":false,"voice":true,"ticking":false,"countdownSeconds":5,"timeMarkers":true,"markerPoints":[300,60,30],"announceNext":true,"flash":true,"haptics":true,"duckMusic":false},"paleColors":true,"keepScreenAwake":false}"#
        defaults.set(Data(old.utf8), forKey: "settings.v1")
        let settings = SettingsStore(defaults: defaults)
        XCTAssertFalse(settings.cue.beeps)
        XCTAssertEqual(settings.cue.countdownSeconds, 5)
        XCTAssertTrue(settings.paleColors, "Old settings must not be reset")
        XCTAssertFalse(settings.keepScreenAwake)
        XCTAssertFalse(settings.saveToHealth)
        XCTAssertEqual(settings.cue.beepStyle, .classic)
    }

    func testNewSettingsPersist() {
        let defaults = UserDefaults(suiteName: "tests-\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        settings.saveToHealth = true
        settings.cue.beepStyle = .bell
        let reloaded = SettingsStore(defaults: defaults)
        XCTAssertTrue(reloaded.saveToHealth)
        XCTAssertEqual(reloaded.cue.beepStyle, .bell)
    }

    // MARK: - Beeps

    func testEveryBeepStyleHasEverySound() {
        for style in BeepStyle.allCases {
            let set = ToneSet.make(style)
            for (name, tones) in [("countdown", set.countdown), ("go", set.go), ("rest", set.restStart), ("tick", set.tick), ("finished", set.finished)] {
                XCTAssertFalse(tones.isEmpty, "\(style) \(name)")
                XCTAssertTrue(tones.allSatisfy { $0.duration > 0 && $0.amplitude > 0 && $0.amplitude <= 1 }, "\(style) \(name)")
            }
        }
    }

    // MARK: - +10 s

    func testAddTimeLengthensTheCurrentInterval() async throws {
        let session = RunSession(name: "T", color: .red, definition: simple(work: 20, rest: 10, rounds: 2),
                                 templateID: nil, settings: makeSettings(CueSettings(beeps: false, voice: false, ticking: false)))
        session.start()
        defer { session.teardown() }
        let before = session.snapshot.remainingInSegment
        let total = session.plan.totalDuration
        session.addTime(10)
        XCTAssertEqual(session.snapshot.remainingInSegment, before + 10, accuracy: 0.5)
        XCTAssertEqual(session.plan.totalDuration, total + 10)
        XCTAssertEqual(session.plan.segments.first?.duration, 30)
    }
}
