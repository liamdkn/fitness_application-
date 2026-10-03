import Foundation
import UserNotifications

/// Keeps two local notifications in step with today's caffeine - "last call"
/// and "wind down" (see `CaffeineReminderPlan`). Like the daily check-in
/// reminder, a local notification can't re-evaluate itself when the moment
/// arrives, so this reschedules a fresh one-time pair whenever something
/// could have changed: launch, returning to the app, and every time a drink
/// is logged or removed. The wording reflects what's been logged by then -
/// a coffee drunk without logging it isn't known to the app.
@MainActor
final class CaffeineReminderService {
    static let shared = CaffeineReminderService()

    private let liquidsRepository = LiquidsRepository()
    private let preferencesRepository = UserPreferencesRepository()

    private init() {}

    func refresh() async {
        let center = UNUserNotificationCenter.current()
        let preferences = try? await preferencesRepository.fetch()
        guard preferences?.caffeineRemindersEnabled ?? true else {
            cancelAll()
            return
        }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let now = Date()
        let halfLife = preferences?.caffeineHalfLifeHours ?? 5
        let bedMinutes = await BedtimeResolver.resolve(preferences).minutes
        let bedtime = CaffeineModel.bedtime(onDayOf: now, minutesAfterMidnight: bedMinutes)
        let day = (try? await liquidsRepository.fetchDay(date: now)) ?? LiquidsDay()
        let typical = (await liquidsRepository.fetchRecentDoses(days: 30)).sorted()
        let typicalDose = typical.isEmpty ? 95 : typical[typical.count / 2]

        let plan = CaffeineReminderPlan.reminders(
            doses: day.caffeineDoses,
            typicalDoseMg: typicalDose,
            bedtime: bedtime,
            targetMg: Double(preferences?.caffeineBedtimeTargetMg ?? 50),
            halfLifeHours: halfLife,
            now: now
        )

        let planned = Set(plan.map { $0.kind.rawValue })
        let stale = [CaffeineReminderPlan.Kind.cutoff, .windDown].map(\.rawValue).filter { !planned.contains($0) }
        center.removePendingNotificationRequests(withIdentifiers: stale)

        for reminder in plan {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate),
                repeats: false
            )
            // Same identifier replaces the earlier request rather than stacking.
            try? await center.add(UNNotificationRequest(identifier: reminder.kind.rawValue, content: content, trigger: trigger))
        }
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [CaffeineReminderPlan.Kind.cutoff.rawValue, CaffeineReminderPlan.Kind.windDown.rawValue]
        )
    }
}
