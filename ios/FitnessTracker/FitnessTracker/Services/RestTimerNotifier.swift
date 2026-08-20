import Foundation
import UserNotifications

/// Schedules a local notification for when the rest timer finishes, so a
/// lifter whose phone is locked/pocketed still gets nudged. Uses a fixed
/// identifier so starting a new rest timer naturally replaces any pending
/// one - no manual bookkeeping of previous requests needed.
enum RestTimerNotifier {
    private static let identifier = "rest-timer"

    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func scheduleRestComplete(after seconds: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = "Time to get back to it."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    static func cancelPending() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
