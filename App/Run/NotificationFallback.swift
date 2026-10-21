import Foundation
import TimerKit
import UserNotifications

/// When all sounds are off we never touch the audio session, so iOS may
/// suspend the app in the background. Local notifications then mark each
/// phase change. They are cancelled as soon as the app is foregrounded.
enum NotificationFallback {
    private static let prefix = "phase-"
    /// iOS keeps at most 64 pending notifications per app.
    private static let limit = 60

    static func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    static func schedule(plan: WorkoutPlan, elapsed: TimeInterval) {
        let center = UNUserNotificationCenter.current()
        cancelAll()
        var scheduled = 0
        for (index, segment) in plan.segments.enumerated() {
            let start = TimeInterval(plan.startOffsets[index])
            guard start > elapsed + 0.5, scheduled < limit else { continue }
            let content = UNMutableNotificationContent()
            content.title = PhaseStyle.name(for: segment)
            content.body = TimeFormat.clock(segment.duration)
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: start - elapsed, repeats: false)
            center.add(UNNotificationRequest(identifier: "\(prefix)\(index)", content: content, trigger: trigger))
            scheduled += 1
        }
        let remaining = TimeInterval(plan.totalDuration) - elapsed
        if remaining > 0.5 {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Workout complete")
            content.body = plan.name
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: remaining, repeats: false)
            center.add(UNNotificationRequest(identifier: "\(prefix)finished", content: content, trigger: trigger))
        }
    }

    static func cancelAll() {
        // This app schedules no other notifications, so clearing all pending is safe
        // and, unlike a filtered async removal, can't race with a new schedule.
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
