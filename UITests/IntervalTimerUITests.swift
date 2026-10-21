import XCTest

/// Drives the real app in the iOS Simulator the way a person would.
/// Screenshots are attached to each test and published by CI.
final class IntervalTimerUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTesting"]
        app.launch()
    }

    // MARK: - Library and editor

    func test01LibraryShowsStarterTimers() {
        XCTAssertTrue(element("timer-Tabata").waitForExistence(timeout: 15))
        XCTAssertTrue(element("timer-HIIT 40/20").exists)
        XCTAssertTrue(element("timer-Boxing rounds").exists)
        snapshot("01-library")
    }

    func test02CreateThenEditATimerInPlace() {
        XCTAssertTrue(element("timer-Tabata").waitForExistence(timeout: 15))
        openAddMenu()
        app.buttons["New timer"].tap()

        let name = app.textFields["nameField"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        replaceText(in: name, with: "Leg day")
        snapshot("02-editor-simple")
        app.buttons["saveButton"].tap()

        let row = element("timer-Leg day")
        XCTAssertTrue(row.waitForExistence(timeout: 5), "New timer not in the library")

        // Edit it: the review complaint was that edits were not kept.
        row.swipeLeft()
        // The row's swipe action, not the nav bar's Edit (reorder) button.
        app.collectionViews.buttons["Edit"].tap()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        replaceText(in: name, with: "Leg day v2")
        app.buttons["saveButton"].tap()

        XCTAssertTrue(element("timer-Leg day v2").waitForExistence(timeout: 5), "Edit was not saved")
        XCTAssertFalse(element("timer-Leg day").exists, "Editing created a copy instead of updating")
        snapshot("03-library-after-edit")
    }

    func test03PresetsGallery() {
        XCTAssertTrue(element("timer-Tabata").waitForExistence(timeout: 15))
        openAddMenu()
        app.buttons["From a preset"].tap()
        let pyramid = listItem(startingWith: "Pyramid")
        XCTAssertTrue(pyramid.waitForExistence(timeout: 5))
        XCTAssertTrue(listItem(startingWith: "EMOM 10").exists)
        snapshot("04-presets")
        pyramid.tap()
        // Picking a preset opens the editor on a copy, in custom mode for the pyramid.
        XCTAssertTrue(app.textFields["nameField"].waitForExistence(timeout: 5))
        snapshot("05-editor-custom-pyramid")
    }

    // MARK: - Running a workout

    func test04RunAWorkoutFromStartToFinish() {
        // Quick test: 5 s get ready, 4 s work, 3 s rest, 4 s work = 16 s.
        startTimer("Quick test")

        let phase = element("phaseName")
        XCTAssertTrue(phase.waitForExistence(timeout: 5))
        XCTAssertTrue(wait(phase, labelContains: "Get ready", timeout: 5), "Got \(phase.label)")
        snapshot("06-run-get-ready")

        XCTAssertTrue(wait(phase, labelContains: "Work", timeout: 5), "Work never started; got \(phase.label)")
        XCTAssertTrue(element("roundCounter").label.contains("1/2"), "Round counter: \(element("roundCounter").label)")
        snapshot("07-run-work")

        // Pause freezes the clock.
        element("pauseButton").tap()
        let frozen = element("countdown").label
        sleep(2)
        XCTAssertEqual(element("countdown").label, frozen, "Clock moved while paused")
        snapshot("08-run-paused")
        element("pauseButton").tap()

        XCTAssertTrue(wait(phase, labelContains: "Rest", timeout: 8), "Rest never started; got \(phase.label)")
        snapshot("09-run-rest")

        let summary = element("summaryTitle")
        XCTAssertTrue(summary.waitForExistence(timeout: 15), "Workout never finished")
        XCTAssertTrue(summary.label.contains("Workout complete"))
        snapshot("10-summary")

        let report = cueReport()
        attach(text: element("cueLog").label, named: "cue-log-foreground")
        XCTAssertEqual(report["starts"], 4, "Expected a start cue for each of the 4 intervals")
        XCTAssertLessThan(report["maxLate"] ?? 99, 0.5, "A cue played late")

        element("doneButton").tap()
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(listItem(startingWith: "Quick test").waitForExistence(timeout: 5), "Workout missing from History")
        snapshot("11-history")
    }

    func test05SkipControls() {
        startTimer("Quick test")
        let phase = element("phaseName")
        XCTAssertTrue(wait(phase, labelContains: "Get ready", timeout: 5))
        element("pauseButton").tap()   // paused, so skips are judged without the clock moving
        element("nextButton").tap()
        XCTAssertTrue(wait(phase, labelContains: "Work", timeout: 5), "Skip forward failed; got \(phase.label)")
        XCTAssertTrue(element("countdown").label.contains("4 seconds"), "Skip should land at the start of Work: \(element("countdown").label)")
        element("previousButton").tap()
        XCTAssertTrue(wait(phase, labelContains: "Get ready", timeout: 5), "Skip back failed; got \(phase.label)")

        element("endButton").tap()
        // The confirmation's button, not the X button that shares its label.
        let confirm = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "End workout", "endButton")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(element("summaryTitle").waitForExistence(timeout: 5))
        XCTAssertTrue(element("summaryTitle").label.contains("Workout ended"))
    }

    /// The core lock-screen check: send the app to the background mid-workout
    /// and confirm cues kept firing on time while it was there. If iOS had
    /// suspended the app, those cues would be missing or late.
    func test06KeepsRunningAndCueingInTheBackground() {
        // Background test: 2 s get ready, 12 s work, 6 s rest, 12 s work = 32 s.
        startTimer("Background test")
        let phase = element("phaseName")
        XCTAssertTrue(wait(phase, labelContains: "Work", timeout: 10), "Work never started; got \(phase.label)")
        sleep(1)

        XCUIDevice.shared.press(.home)
        sleep(14)   // spans the end of round 1 (countdown) and the start of the rest
        app.activate()

        XCTAssertTrue(phase.waitForExistence(timeout: 10))
        sleep(1)   // let the return-to-app transition finish before the screenshot
        snapshot("12-after-background")
        let log = element("cueLog").label
        attach(text: log, named: "cue-log-background")
        let report = cueReport()

        XCTAssertEqual(report["audio"], 1, "Tone engine not running: \(log)")
        XCTAssertGreaterThanOrEqual(report["bg"] ?? 0, 3, "Too few cues fired while in the background: \(log)")
        XCTAssertLessThan(report["maxLate"] ?? 99, 1.0, "Cues were late, so the app was suspended: \(log)")
        XCTAssertTrue(phase.label.localizedCaseInsensitiveContains("Rest") || phase.label.localizedCaseInsensitiveContains("Work"),
                      "Unexpected phase after returning: \(phase.label)")
    }

    // MARK: - Other tabs

    func test07StopwatchLapsAndHistory() {
        app.tabBars.buttons["Stopwatch"].tap()
        app.buttons["Start"].tap()
        sleep(1)
        app.buttons["Lap"].tap()
        sleep(1)
        app.buttons["Stop"].tap()
        XCTAssertTrue(listItem(startingWith: "Lap 1").waitForExistence(timeout: 3))
        snapshot("13-stopwatch")
        app.buttons["Reset"].tap()

        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(listItem(startingWith: "Stopwatch").waitForExistence(timeout: 5), "Stopwatch session missing from History")
    }

    func test08Settings() {
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.switches["Voice guidance"].waitForExistence(timeout: 5))
        snapshot("14-settings")
        app.swipeUp()
        app.swipeUp()
        let footer = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Free forever")).firstMatch
        XCTAssertTrue(footer.waitForExistence(timeout: 3), "Free-forever note missing from Settings")
        snapshot("15-settings-bottom")
    }

    // MARK: - Helpers

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// First element inside the screen's list whose label starts with `text`.
    private func listItem(startingWith text: String) -> XCUIElement {
        app.collectionViews.firstMatch
            .descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", text))
            .firstMatch
    }

    /// The toolbar "+" menu. XCUITest can't AX-scroll nav bar menus, so tap its centre directly.
    private func openAddMenu() {
        let add = app.buttons["Add timer"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }

    private func startTimer(_ name: String) {
        let row = element("timer-\(name)")
        XCTAssertTrue(row.waitForExistence(timeout: 15), "No timer named \(name)")
        row.tap()
        if !element("phaseName").waitForExistence(timeout: 6) {
            row.tap()   // a tap during launch can be swallowed; try once more
        }
        XCTAssertTrue(element("phaseName").waitForExistence(timeout: 10), "Run screen never opened for \(name)")
    }

    private func wait(_ element: XCUIElement, labelContains text: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS[c] %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    private func replaceText(in field: XCUIElement, with text: String) {
        // Tap at the right edge so the cursor lands after the existing text.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let existing = (field.value as? String) ?? ""
        if !existing.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count + 2))
        }
        field.typeText(text)
    }

    /// Parses "starts=4 countdowns=5 bg=0 maxLate=0.05 audio=1".
    private func cueReport() -> [String: Double] {
        var result: [String: Double] = [:]
        for pair in element("cueLog").label.split(separator: " ") {
            let parts = pair.split(separator: "=")
            if parts.count == 2, let value = Double(parts[1]) {
                result[String(parts[0])] = value
            }
        }
        return result
    }

    private func snapshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attach(text: String, named name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
