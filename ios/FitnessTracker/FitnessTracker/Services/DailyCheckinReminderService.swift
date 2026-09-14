import Foundation
import UserNotifications

/// Schedules a local 9am reminder for today's daily check-in, and keeps it
/// in sync with whether that check-in is actually still outstanding -
/// mirrors `HealthSyncService`'s shape (singleton, driven by `MainTabView`'s
/// `.task` + `.onChange(of: scenePhase)`).
///
/// Local notifications can't carry server-side "is this still true?" logic,
/// so instead of one repeating trigger this reschedules a fresh one-time
/// 9am request every time `refresh()` runs (launch, foreground) and cancels
/// it the moment the check-in is actually completed - rather than letting a
/// stale reminder fire after someone already checked in.
@MainActor
final class DailyCheckinReminderService {
    static let shared = DailyCheckinReminderService()

    /// Stable id so rescheduling or cancelling today's reminder replaces/
    /// removes the same request instead of stacking duplicates.
    private static let reminderIdentifier = "daily-checkin-reminder"
    private static let reminderHour = 9

    private let dailyCheckinRepository = DailyCheckinRepository()

    private init() {}

    /// Requests permission once - call at a natural moment (app launch),
    /// same as `HealthSyncService.requestAuthorizationAndSync()`. A denial
    /// just means `refresh()`'s own authorization check below no-ops.
    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Reflects whichever is true right now: cancels the reminder if
    /// today's check-in is already done, or (re)schedules it for 9am today
    /// if it's not and 9am hasn't passed yet.
    func refresh() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let alreadyCompleted = (try? await dailyCheckinRepository.fetch(date: Date())) != nil
        guard !alreadyCompleted else {
            cancelTodaysReminder()
            return
        }

        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = Self.reminderHour
        components.minute = 0
        guard let fireDate = calendar.date(from: components), fireDate > Date() else {
            // 9am has already passed today - nothing to schedule until
            // tomorrow's `refresh()` call recomputes this against a new day.
            cancelTodaysReminder()
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Daily Check-In"
        content.body = "You haven't logged today's check-in yet."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents([.hour, .minute], from: fireDate),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: Self.reminderIdentifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    /// Called the moment a check-in is saved, so completing it at 8:59
    /// doesn't still get a reminder at 9:00 - `refresh()` alone would only
    /// pick that up on the next launch/foreground.
    func cancelTodaysReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.reminderIdentifier])
    }
}
