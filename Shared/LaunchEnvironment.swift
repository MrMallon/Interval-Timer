@_exported import TimerKit
import Foundation

/// How the app was launched. Tests get a clean, in-memory app every launch.
enum LaunchEnvironment {
    /// Set by the UI tests via the `-uiTesting` launch argument.
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-uiTesting")

    /// True when the app is hosting the unit-test bundle.
    static let isUnitTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    static var usesInMemoryStore: Bool { isUITesting || isUnitTesting }
}
