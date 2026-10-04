import Foundation
import UserNotifications

/// Schedules a local reminder for today's daily check-in, 15 minutes after
/// you usually wake (9am until Health has enough sleep data), and keeps it
/// in sync with whether that check-in is actually still outstanding -
/// mirrors `HealthSyncService`'s shape (singleton, driven by `MainTabView`'s
/// `.task` + `.onChange(of: scenePhase)`).
///
/// Local notifications can't carry server-side "is this still true?" logic,
/// so instead of one repeating trigger this reschedules a fresh one-time
/// request every time `refresh()` runs (launch, foreground) and cancels
/// it the moment the check-in is actually completed - rather than letting a
/// stale reminder fire after someone already checked in.
@MainActor
final class DailyCheckinReminderService {
    static let shared = DailyCheckinReminderService()

    /// Stable id so rescheduling or cancelling today's reminder replaces/
    /// removes the same request instead of stacking duplicates.
    private static let reminderIdentifier = "daily-checkin-reminder"
    /// Used until Health has enough nights to say when you wake.
    private static let fallbackMinutes = 9 * 60
    /// The nudge goes this long after your usual wake time.
    private static let minutesAfterWake = 15

    private let dailyCheckinRepository = DailyCheckinRepository()

    private init() {}

    /// Requests permission once - call at a natural moment (app launch),
    /// same as `HealthSyncService.requestAuthorizationAndSync()`. A denial
    /// just means `refresh()`'s own authorization check below no-ops.
    func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Reflects whichever is true right now: cancels the reminder if
    /// today's check-in is already done, or (re)schedules it for the wake-based time today
    /// if it's not and that time hasn't passed yet.
    func refresh() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        // Done for today if there's a check-in, or a weigh-in from a scale or Health.
        let checkedIn = (try? await dailyCheckinRepository.fetch(date: Date())) != nil
        let calendar = Calendar.current
        let weighedIn = ((try? await BodyWeightRepository().fetchRecent(days: 1)) ?? [])
            .contains { calendar.isDateInToday($0.loggedAt) }
        guard !checkedIn, !weighedIn else {
            cancelTodaysReminder()
            return
        }

        let wake = await WakeTimeResolver.typicalWakeMinutes()
        let minutes = wake.map { min(max($0 + Self.minutesAfterWake, 5 * 60), 12 * 60) } ?? Self.fallbackMinutes
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = minutes / 60
        components.minute = minutes % 60
        guard let fireDate = calendar.date(from: components), fireDate > Date() else {
            // That time has already passed today - nothing to schedule until
            // tomorrow's `refresh()` call recomputes this against a new day.
            cancelTodaysReminder()
            return
        }

        let missed = await missedDays()
        let content = UNMutableNotificationContent()
        content.sound = .default
        if missed >= 2 {
            content.title = "\(missed) days without a weigh-in"
            content.body = "Weigh in this morning and do today's check-in - your trend and calorie estimate need the data."
        } else {
            content.title = "Morning weigh-in"
            content.body = "Weigh in and do today's check-in."
        }

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents([.hour, .minute], from: fireDate),
            repeats: false
        )
        let request = UNNotificationRequest(identifier: Self.reminderIdentifier, content: content, trigger: trigger)
        try? await center.add(request)
    }

    /// Days in a row, up to yesterday, with nothing logged.
    private func missedDays() async -> Int {
        guard let logged = await CheckinGapService().loggedDates() else { return 0 }
        return CheckinGaps.consecutiveMissed(logged: logged, today: Date())
    }

    /// Called the moment a check-in is saved, so completing it at 8:59
    /// doesn't still get a reminder at 9:00 - `refresh()` alone would only
    /// pick that up on the next launch/foreground.
    func cancelTodaysReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.reminderIdentifier])
    }
}
