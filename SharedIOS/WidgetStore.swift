import Foundation

/// A saved timer as the home-screen widget sees it.
struct WidgetTimer: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var colorName: String
    var summary: String
}

/// The app writes its timer list here; the widget reads it.
/// Lives in the shared App Group. If the App Group isn't available (for
/// example some free sideloading setups) the widget simply shows a prompt
/// to open the app.
enum WidgetStore {
    static let appGroup = "group.com.mrmallon.intervaltimer"
    static let widgetKind = "QuickStart"
    private static let key = "widget.timers.v1"
    private static let lastKey = "widget.lastWorkout.v1"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func save(_ timers: [WidgetTimer]) {
        guard let defaults, let data = try? JSONEncoder().encode(timers) else { return }
        defaults.set(data, forKey: key)
    }

    /// The most recent interval workout, for the widget's "Repeat" button. nil clears it.
    static func saveLast(_ timer: WidgetTimer?) {
        guard let defaults else { return }
        if let timer, let data = try? JSONEncoder().encode(timer) {
            defaults.set(data, forKey: lastKey)
        } else {
            defaults.removeObject(forKey: lastKey)
        }
    }

    static func loadLast() -> WidgetTimer? {
        guard let data = defaults?.data(forKey: lastKey) else { return nil }
        return try? JSONDecoder().decode(WidgetTimer.self, from: data)
    }

    static func load() -> [WidgetTimer] {
        guard
            let data = defaults?.data(forKey: key),
            let timers = try? JSONDecoder().decode([WidgetTimer].self, from: data)
        else { return [] }
        return timers
    }
}

/// `intervaltimer://start/<timer id>` opens the app and starts that timer.
/// `intervaltimer://repeat` starts the most recent workout again.
enum DeepLink: Equatable {
    case start(UUID)
    case repeatLast

    static let scheme = "intervaltimer"

    var url: URL {
        switch self {
        case .start(let id): return URL(string: "\(Self.scheme)://start/\(id.uuidString)")!
        case .repeatLast: return URL(string: "\(Self.scheme)://repeat")!
        }
    }

    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme else { return nil }
        if url.host?.lowercased() == "repeat" {
            self = .repeatLast
            return
        }
        guard url.host?.lowercased() == "start" else { return nil }
        let idString = url.pathComponents.first(where: { $0 != "/" }) ?? ""
        guard let id = UUID(uuidString: idString) else { return nil }
        self = .start(id)
    }
}
