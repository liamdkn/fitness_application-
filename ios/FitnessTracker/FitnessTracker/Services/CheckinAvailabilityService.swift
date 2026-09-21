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
    /// user's current check-in week - the row itself always stays on the
    /// Dashboard (see `CheckInsCard`), same as Daily; this only toggles its
    /// checkmark, it doesn't hide anything.
    @Published var weeklyCompletedThisWeek = false

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
