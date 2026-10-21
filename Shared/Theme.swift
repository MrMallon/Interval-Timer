import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
import TimerKit

/// Colour a user can pick for a saved timer.
enum ThemeColor: String, CaseIterable, Identifiable, Codable {
    case red, orange, yellow, green, teal, blue, indigo, purple, pink

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .red: return Color(red: 0.90, green: 0.28, blue: 0.30)
        case .orange: return Color(red: 0.96, green: 0.52, blue: 0.20)
        case .yellow: return Color(red: 0.95, green: 0.74, blue: 0.16)
        case .green: return Color(red: 0.20, green: 0.68, blue: 0.42)
        case .teal: return Color(red: 0.12, green: 0.64, blue: 0.66)
        case .blue: return Color(red: 0.20, green: 0.48, blue: 0.92)
        case .indigo: return Color(red: 0.36, green: 0.36, blue: 0.86)
        case .purple: return Color(red: 0.58, green: 0.36, blue: 0.82)
        case .pink: return Color(red: 0.90, green: 0.36, blue: 0.62)
        }
    }

    var accessibilityName: String {
        rawValue.capitalized
    }
}

/// Full-screen colours for each phase of the run screen.
enum PhaseStyle {
    static func color(for kind: PhaseKind?, pale: Bool) -> Color {
        let base: Color
        switch kind {
        case .prepare: base = Color(red: 0.96, green: 0.62, blue: 0.16)
        case .work: base = Color(red: 0.88, green: 0.24, blue: 0.27)
        case .rest: base = Color(red: 0.16, green: 0.62, blue: 0.40)
        case .cycleRest: base = Color(red: 0.18, green: 0.45, blue: 0.86)
        case .coolDown: base = Color(red: 0.50, green: 0.36, blue: 0.80)
        case nil: base = Color(red: 0.20, green: 0.22, blue: 0.26)
        }
        return pale ? base.blended(with: .white, amount: 0.45) : base
    }

    static func name(for kind: PhaseKind) -> String {
        switch kind {
        case .prepare: return String(localized: "Get ready")
        case .work: return String(localized: "Work")
        case .rest: return String(localized: "Rest")
        case .cycleRest: return String(localized: "Cycle rest")
        case .coolDown: return String(localized: "Cool down")
        }
    }

    static func symbol(for kind: PhaseKind) -> String {
        switch kind {
        case .prepare: return "hourglass"
        case .work: return "flame.fill"
        case .rest: return "pause.circle.fill"
        case .cycleRest: return "arrow.triangle.2.circlepath"
        case .coolDown: return "snowflake"
        }
    }

    /// Display name for a segment: its custom label, else the phase name.
    static func name(for segment: Segment) -> String {
        if let label = segment.label, !label.trimmingCharacters(in: .whitespaces).isEmpty {
            return label
        }
        return name(for: segment.kind)
    }
}

extension Color {
    /// Linear blend toward another colour (iOS 18 has a built-in; this works on 17).
    func blended(with other: Color, amount: Double) -> Color {
        let a = UIColor(self)
        let b = UIColor(other)
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = CGFloat(max(0, min(1, amount)))
        return Color(
            red: Double(r1 + (r2 - r1) * t),
            green: Double(g1 + (g2 - g1) * t),
            blue: Double(b1 + (b2 - b1) * t),
            opacity: Double(a1 + (a2 - a1) * t)
        )
    }
}

/// Human summary of a timer, e.g. "8 × 0:20 / 0:10 · 4:00".
enum TimerSummary {
    static func describe(_ definition: TimerDefinition) -> String {
        let plan = WorkoutPlan(name: "", definition: definition)
        let total = TimeFormat.clock(plan.totalDuration)
        switch definition {
        case .simple(let config):
            var text = "\(config.rounds) × \(TimeFormat.clock(config.work))"
            if config.rest > 0 { text += " / \(TimeFormat.clock(config.rest))" }
            if config.cycles > 1 { text += " × \(config.cycles) " + String(localized: "cycles") }
            return text + " · " + total
        case .custom:
            return String(localized: "\(plan.workCount) intervals") + " · " + total
        }
    }
}
