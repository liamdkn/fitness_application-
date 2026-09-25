import Foundation

enum ScheduledDayType: String, Codable, CaseIterable, Identifiable {
    case workout
    case activeRest = "active_rest"
    case rest

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .workout: "Workout"
        case .activeRest: "Active Rest"
        case .rest: "Rest"
        }
    }
}

/// One weekday's slot in the fixed weekly schedule - replaces the old
/// "advance through routine_days by completing a workout" cycle with a
/// calendar the split editor sets directly (see `WeeklyScheduleRepository`,
/// `StartWorkoutView`'s day carousel). `weekday` is Swift's own
/// `Calendar.Component.weekday` numbering (1 = Sunday ... 7 = Saturday).
struct WeeklyScheduleDay: Codable, Identifiable, Hashable {
    let id: UUID
    let routineId: UUID
    let weekday: Int
    let dayType: ScheduledDayType
    let routineDayId: UUID?
    let cardioType: CardioType?

    enum CodingKeys: String, CodingKey {
        case id
        case routineId = "routine_id"
        case weekday
        case dayType = "day_type"
        case routineDayId = "routine_day_id"
        case cardioType = "cardio_type"
    }

    static let weekdaySymbols: [Int: String] = [
        1: "Sunday", 2: "Monday", 3: "Tuesday", 4: "Wednesday",
        5: "Thursday", 6: "Friday", 7: "Saturday"
    ]

    var weekdayName: String { Self.weekdaySymbols[weekday] ?? "" }
}
