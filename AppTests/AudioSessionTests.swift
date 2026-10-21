import AVFoundation
import XCTest
@testable import IntervalTimer

/// Checks the app's audio session against the real iOS audio APIs in the simulator.
/// These settings are what decide whether Spotify / Apple Music keep playing,
/// get quieter, or stop when the timer makes a sound.
@MainActor
final class AudioSessionTests: XCTestCase {
    private var session: AVAudioSession { AVAudioSession.sharedInstance() }

    override func setUp() async throws {
        // Start each test from a neutral category, as if no workout had run.
        try session.setCategory(.ambient)
    }

    func testDefaultSettingsMixWithMusicAndNeverDuck() {
        let player = AudioCuePlayer()
        player.activate(settings: CueSettings())
        defer { player.deactivate() }

        XCTAssertTrue(player.isSessionActive)
        XCTAssertEqual(session.category, .playback, "Playback category is required to keep sounding on a locked screen")
        XCTAssertTrue(session.categoryOptions.contains(.mixWithOthers), "Must mix with the user's music")
        XCTAssertFalse(session.categoryOptions.contains(.duckOthers), "Must not lower the user's music by default")
    }

    func testToneEngineRunsSoTheTimerSurvivesTheLockScreen() {
        let player = AudioCuePlayer()
        player.activate(settings: CueSettings())
        defer { player.deactivate() }

        XCTAssertTrue(player.isEngineRunning, "The always-on tone engine is what keeps the app running in the background")
    }

    func testAllSoundsOffNeverTouchesTheAudioSession() {
        let player = AudioCuePlayer()
        player.activate(settings: CueSettings(beeps: false, voice: false, ticking: false))
        defer { player.deactivate() }

        XCTAssertFalse(player.isSessionActive)
        XCTAssertEqual(session.category, .ambient, "With every sound off the app must leave audio alone")
    }

    func testSpeakingDoesNotDuckMusicWhenDuckingIsOff() async throws {
        let player = AudioCuePlayer()
        player.activate(settings: CueSettings(voice: true, duckMusic: false))
        defer { player.deactivate() }

        player.speak("Work")
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertFalse(session.categoryOptions.contains(.duckOthers))
    }

    func testDucksOnlyWhileSpeakingWhenEnabled() async throws {
        let player = AudioCuePlayer()
        player.activate(settings: CueSettings(voice: true, duckMusic: true))
        defer { player.deactivate() }

        XCTAssertFalse(session.categoryOptions.contains(.duckOthers), "No ducking before anything is said")
        player.speak("Rest")
        XCTAssertTrue(session.categoryOptions.contains(.duckOthers), "Music lowers while the voice speaks")

        try await waitUntil(10, "Music volume was never restored after speaking") {
            !self.session.categoryOptions.contains(.duckOthers)
        }
        XCTAssertTrue(session.categoryOptions.contains(.mixWithOthers))
    }
}
