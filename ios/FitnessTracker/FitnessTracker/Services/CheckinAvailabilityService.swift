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
    @Published var weeklyDue = false

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
            let hasWeeklyCheckin = try await weeklyCheckinRepository.hasCheckinSince(weekStart)
            weeklyDue = !hasWeeklyCheckin
        } catch {
            // Don't block the dashboard on a check-in availability query failure.
        }
    }

    func checkinCompleted(_ kind: PendingCheckin) {
        switch kind {
        case .daily:
            dailyCompletedToday = true
            DailyCheckinReminderService.shared.cancelTodaysReminder()
        case .weekly: weeklyDue = false
        }
    }
}
