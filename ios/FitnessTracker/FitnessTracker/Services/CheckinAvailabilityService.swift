import Combine
import Foundation

enum PendingCheckin {
    case daily
    case weekly
}

@MainActor
final class CheckinAvailabilityService: ObservableObject {
    static let shared = CheckinAvailabilityService()

    /// Drives the persistent Dashboard Check-Ins card. Check-ins are opened
    /// at the user's discretion, not auto-prompted.
    @Published var dailyCompletedToday = false
    /// Whether a weekly check-in has been filed since the start of the
    /// user's current check-in week - only meaningful while `weeklyDueToday`
    /// is also true (see that property); this just toggles the row's
    /// checkmark, same as `dailyCompletedToday` does for Daily.
    @Published var weeklyCompletedThisWeek = false
    /// Whether today is the user's configured weekly check-in day - unlike
    /// Daily (which is relevant every single day), the Weekly row only
    /// belongs on the Dashboard on its one scheduled day. It still doesn't
    /// vanish the instant it's completed (same fix as Daily - reopening to
    /// fix a mistyped answer needs the row to still be there), it just
    /// stops showing at all once that day has passed rather than sitting
    /// there, checked off, for the rest of the week.
    @Published var weeklyDueToday = false

    private let dailyCheckinRepository = DailyCheckinRepository()
    private let weeklyCheckinRepository = WeeklyCheckinRepository()
    private let preferencesRepository = UserPreferencesRepository()

    private init() {}

    func refresh() async {
        do {
            let todayCheckin = try await dailyCheckinRepository.fetch(date: Date())
            dailyCompletedToday = todayCheckin != nil

            let preferences = try await preferencesRepository.fetch()
            let weekStart = DateFormatting.startOfCheckinWeek(weekday: preferences.weeklyCheckinWeekday)
            weeklyCompletedThisWeek = try await weeklyCheckinRepository.hasCheckinSince(weekStart)
            weeklyDueToday = Calendar.current.component(.weekday, from: Date()) == preferences.weeklyCheckinWeekday
        } catch {
            // Don't block the dashboard on a check-in availability query failure.
        }
    }

    func checkinCompleted(_ kind: PendingCheckin) {
        switch kind {
        case .daily:
            dailyCompletedToday = true
            DailyCheckinReminderService.shared.cancelTodaysReminder()
        case .weekly: weeklyCompletedThisWeek = true
        }
    }
}
