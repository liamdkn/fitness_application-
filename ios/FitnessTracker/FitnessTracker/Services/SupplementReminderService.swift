import ActivityKit
import Foundation
import UserNotifications

/// Keeps supplement reminders and the Live Activity in step with what's been
/// taken. Like the other reminder services it re-reads the day each time it
/// runs (launch, foreground, a dose logged) and replaces what's pending, so a
/// reminder for a dose already taken never goes off.
@MainActor
final class SupplementReminderService {
    static let shared = SupplementReminderService()

    private static let prefix = "supplement-"
    private let repository = SupplementRepository()
    private var activity: Activity<SupplementActivityAttributes>?
    private var isRefreshing = false

    private init() {}

    /// Called once at launch: lets the Live Activity's tick button reach the app.
    func installIntentHandler() {
        SupplementIntentBridge.handler = { [weak self] id in
            await self?.take(supplementId: id)
        }
    }

    /// Logs one dose of a supplement at its planned amount for today.
    func take(supplementId: UUID, at: Date = Date()) async {
        guard let days = try? await repository.day(date: at),
              let day = days.first(where: { $0.supplement.id == supplementId }) else { return }
        _ = try? await repository.take(supplementId: supplementId, amount: day.amountPerServing, at: at)
        await refresh()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // Ticks made from the Live Activity while the app wasn't ready.
        for pending in PendingSupplementTakes.drain() {
            if let days = try? await repository.day(date: pending.at),
               let day = days.first(where: { $0.supplement.id == pending.supplementId }) {
                _ = try? await repository.take(supplementId: pending.supplementId, amount: day.amountPerServing, at: pending.at)
            }
        }

        guard let days = try? await repository.day(date: Date()) else { return }
        await scheduleReminders(days)
        await updateActivity(days)
    }

    // MARK: Reminders

    private func scheduleReminders(_ days: [SupplementDay]) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(Self.prefix) })

        let calendar = Calendar.current
        let now = Date()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        for day in days {
            let times = day.supplement.reminderTimes.sorted()
            for (index, minutes) in times.enumerated() {
                // Today's reminders are for the doses not yet taken: with 1 of
                // 2 done, the first reminder is skipped.
                if index >= day.taken, let fire = date(on: now, minutes: minutes), fire > now {
                    await add(day, index: index, fire: fire, suffix: "today")
                }
                // Tomorrow's, in case the app isn't opened first thing.
                if index < day.supplement.servingsPerDay, let fire = date(on: tomorrow, minutes: minutes) {
                    await add(day, index: index, fire: fire, suffix: "tomorrow")
                }
            }
        }
    }

    private func date(on day: Date, minutes: Int) -> Date? {
        Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day)
    }

    private func add(_ day: SupplementDay, index: Int, fire: Date, suffix: String) async {
        let content = UNMutableNotificationContent()
        content.title = day.supplement.name
        content.body = "Time for \(day.supplement.amountText(day.amountPerServing))."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: "\(Self.prefix)\(day.supplement.id.uuidString)-\(index)-\(suffix)", content: content, trigger: trigger
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: Live Activity

    /// Shown while anything with a reminder is still to take; gone once the day's
    /// doses are done. Started only from the foreground, which ActivityKit requires.
    private func updateActivity(_ days: [SupplementDay]) async {
        let tracked = days.filter { !$0.supplement.reminderTimes.isEmpty || $0.taken > 0 }
        let items = tracked.map {
            SupplementActivityAttributes.Item(
                id: $0.supplement.id, name: $0.supplement.name, taken: $0.taken,
                goal: $0.servingsGoal, amountText: $0.supplement.amountText($0.amountPerServing)
            )
        }
        let state = SupplementActivityAttributes.ContentState(items: items)
        let existing = Activity<SupplementActivityAttributes>.activities
        let allDone = items.isEmpty || state.takenTotal >= state.goalTotal
        let today = DateFormatting.isoDate(Date())

        if allDone {
            for current in existing { await current.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(60 * 20))) }
            activity = nil
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let endOfDay = Calendar.current.startOfDay(for: Date()).addingTimeInterval(24 * 3600)
        let content = ActivityContent(state: state, staleDate: endOfDay)
        if let current = existing.first(where: { $0.attributes.day == today }) {
            await current.update(content)
            activity = current
        } else {
            for old in existing { await old.end(nil, dismissalPolicy: .immediate) }
            activity = try? Activity.request(attributes: SupplementActivityAttributes(day: today), content: content, pushType: nil)
        }
    }

    /// Sign-out or account switch.
    func clear() async {
        for current in Activity<SupplementActivityAttributes>.activities { await current.end(nil, dismissalPolicy: .immediate) }
        activity = nil
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix(Self.prefix) })
        PendingSupplementTakes.clear()
    }
}
