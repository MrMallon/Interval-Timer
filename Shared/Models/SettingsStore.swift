import Foundation
import Observation
import TimerKit

/// App-wide preferences, persisted to UserDefaults.
@Observable
final class SettingsStore {
    var cue: CueSettings { didSet { save() } }
    /// Softer phase colours ("Pale colours" mode).
    var paleColors: Bool { didSet { save() } }
    /// Keep the screen on while a workout runs.
    var keepScreenAwake: Bool { didSet { save() } }
    /// Save finished workouts to Apple Health. Off until the user turns it on.
    var saveToHealth: Bool { didSet { save() } }
    /// Apple Watch: show live heart rate during a workout. Off until the user
    /// turns it on, because it means asking to read heart rate from Health.
    var showHeartRate: Bool { didSet { save() } }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private static let key = "settings.v1"

    private struct Stored: Codable {
        var cue: CueSettings
        var paleColors: Bool
        var keepScreenAwake: Bool
        var saveToHealth: Bool
        var showHeartRate: Bool

        init(cue: CueSettings, paleColors: Bool, keepScreenAwake: Bool, saveToHealth: Bool, showHeartRate: Bool) {
            self.cue = cue
            self.paleColors = paleColors
            self.keepScreenAwake = keepScreenAwake
            self.saveToHealth = saveToHealth
            self.showHeartRate = showHeartRate
        }

        /// Settings saved by older versions lack newer keys; those get defaults.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            cue = try c.decodeIfPresent(CueSettings.self, forKey: .cue) ?? .default
            paleColors = try c.decodeIfPresent(Bool.self, forKey: .paleColors) ?? false
            keepScreenAwake = try c.decodeIfPresent(Bool.self, forKey: .keepScreenAwake) ?? true
            saveToHealth = try c.decodeIfPresent(Bool.self, forKey: .saveToHealth) ?? false
            showHeartRate = try c.decodeIfPresent(Bool.self, forKey: .showHeartRate) ?? false
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            cue = stored.cue
            paleColors = stored.paleColors
            keepScreenAwake = stored.keepScreenAwake
            saveToHealth = stored.saveToHealth
            showHeartRate = stored.showHeartRate
        } else {
            cue = .default
            paleColors = false
            keepScreenAwake = true
            saveToHealth = false
            showHeartRate = false
        }
    }

    private func save() {
        let stored = Stored(cue: cue, paleColors: paleColors, keepScreenAwake: keepScreenAwake,
                            saveToHealth: saveToHealth, showHeartRate: showHeartRate)
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
