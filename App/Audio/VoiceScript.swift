import Foundation
import TimerKit

/// Turns cue events into spoken lines.
enum VoiceScript {
    static func line(for event: CueEvent, plan: WorkoutPlan) -> String? {
        switch event {
        case .segmentStart(let index):
            guard plan.segments.indices.contains(index) else { return nil }
            return segmentStart(plan.segments[index], plan: plan)

        case .countdown(let secondsLeft, _):
            return "\(secondsLeft)"

        case .timeRemaining(let seconds, _):
            return remaining(seconds)

        case .upNext(let index):
            guard plan.segments.indices.contains(index) else { return nil }
            return upNext(plan.segments[index], plan: plan)

        case .tick:
            return nil

        case .finished:
            return String(localized: "Workout complete. Great job!")
        }
    }

    private static func segmentStart(_ segment: Segment, plan: WorkoutPlan) -> String {
        let name = PhaseStyle.name(for: segment)
        switch segment.kind {
        case .work:
            return name
        case .cycleRest:
            if plan.cycleCount > 1 {
                return String(localized: "Rest. Cycle \(segment.cycle) of \(plan.cycleCount) complete.")
            }
            return name
        case .prepare, .rest, .coolDown:
            return name
        }
    }

    private static func upNext(_ segment: Segment, plan: WorkoutPlan) -> String {
        switch segment.kind {
        case .work:
            var parts: [String] = []
            if let label = segment.label, !label.trimmingCharacters(in: .whitespaces).isEmpty {
                parts.append(label)
            }
            if plan.cycleCount > 1, segment.round == 1 {
                parts.append(String(localized: "cycle \(segment.cycle) of \(plan.cycleCount)"))
            }
            if plan.roundsPerCycle > 1, segment.round > 0 {
                parts.append(String(localized: "round \(segment.round) of \(plan.roundsPerCycle)"))
            }
            if parts.isEmpty { parts.append(PhaseStyle.name(for: .work)) }
            return String(localized: "Next: \(parts.joined(separator: ", "))")
        default:
            return String(localized: "Next: \(PhaseStyle.name(for: segment))")
        }
    }

    private static func remaining(_ seconds: Int) -> String {
        if seconds >= 60, seconds % 60 == 0 {
            let minutes = seconds / 60
            return minutes == 1
                ? String(localized: "1 minute left")
                : String(localized: "\(minutes) minutes left")
        }
        return String(localized: "\(seconds) seconds left")
    }
}
