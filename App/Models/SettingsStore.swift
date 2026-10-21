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

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private static let key = "settings.v1"

    private struct Stored: Codable {
        var cue: CueSettings
        var paleColors: Bool
        var keepScreenAwake: Bool
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            cue = stored.cue
            paleColors = stored.paleColors
            keepScreenAwake = stored.keepScreenAwake
        } else {
            cue = .default
            paleColors = false
            keepScreenAwake = true
        }
    }

    private func save() {
        let stored = Stored(cue: cue, paleColors: paleColors, keepScreenAwake: keepScreenAwake)
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
