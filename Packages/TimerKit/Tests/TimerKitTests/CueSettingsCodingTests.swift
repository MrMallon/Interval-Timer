import XCTest
@testable import TimerKit

final class CueSettingsCodingTests: XCTestCase {
    func testSettingsSavedBeforeVoicePickerStillLoad() throws {
        // Exactly what version 1.0 wrote: no voiceIdentifier key.
        let old = """
        {"beeps":false,"voice":true,"ticking":true,"countdownSeconds":5,"timeMarkers":false,
         "markerPoints":[60,30],"announceNext":false,"flash":false,"haptics":false,"duckMusic":true}
        """
        let settings = try JSONDecoder().decode(CueSettings.self, from: Data(old.utf8))
        XCTAssertFalse(settings.beeps)
        XCTAssertTrue(settings.ticking)
        XCTAssertEqual(settings.countdownSeconds, 5)
        XCTAssertEqual(settings.markerPoints, [60, 30])
        XCTAssertTrue(settings.duckMusic)
        XCTAssertNil(settings.voiceIdentifier, "No saved voice means automatic")
    }

    func testChosenVoiceRoundTrips() throws {
        let settings = CueSettings(voiceIdentifier: "com.apple.voice.premium.en-GB.Serena")
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(CueSettings.self, from: data), settings)
    }

    func testMissingKeysFallBackToDefaults() throws {
        let settings = try JSONDecoder().decode(CueSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings, CueSettings())
    }
}
