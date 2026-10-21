import AVFoundation
import XCTest
@testable import IntervalTimer

/// Polls `condition` on the main actor until it is true or the timeout passes.
@MainActor
func waitUntil(
    _ timeout: TimeInterval,
    _ message: String = "Timed out waiting for condition",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: () -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline {
            XCTFail(message, file: file, line: line)
            return
        }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
}

/// Posts the same notification iOS sends when a phone call, Siri or an alarm takes over audio.
func postAudioInterruption(began: Bool, shouldResume: Bool = false) {
    var info: [AnyHashable: Any] = [
        AVAudioSessionInterruptionTypeKey: (began
            ? AVAudioSession.InterruptionType.began
            : AVAudioSession.InterruptionType.ended).rawValue
    ]
    if !began, shouldResume {
        info[AVAudioSessionInterruptionOptionKey] = AVAudioSession.InterruptionOptions.shouldResume.rawValue
    }
    NotificationCenter.default.post(
        name: AVAudioSession.interruptionNotification,
        object: AVAudioSession.sharedInstance(),
        userInfo: info
    )
}

@MainActor
func makeSettings(_ cue: CueSettings = CueSettings()) -> SettingsStore {
    let defaults = UserDefaults(suiteName: "tests-\(UUID().uuidString)")!
    let settings = SettingsStore(defaults: defaults)
    settings.cue = cue
    settings.keepScreenAwake = false
    return settings
}

func simple(prepare: Int = 0, work: Int, rest: Int = 0, rounds: Int = 1, cycles: Int = 1) -> TimerDefinition {
    .simple(SimpleConfig(prepare: prepare, work: work, rest: rest, rounds: rounds, cycles: cycles, restBetweenCycles: 0, coolDown: 0))
}
