import Foundation

/// What kind of day each weekday is in the active split - used by Nutrition
/// (no Preworkout meal on a rest day) and anything else that depends on
/// whether you train. Remembered for offline use.
struct TrainingDayService {
    private let routineRepository = RoutineRepository()
    private let scheduleRepository = WeeklyScheduleRepository()

    /// Weekday (1 = Sunday ... 7) to day type. Empty when there's no active
    /// split, in which case nothing should be treated as a rest day.
    func weekdayTypes() async -> [Int: ScheduledDayType] {
        let stored: [String: String]? = try? await cachedRead(key: "weekday-types") {
            guard let routine = try await routineRepository.fetchActiveRoutine() else { return [String: String]() }
            let schedule = try await scheduleRepository.fetchSchedule(routineId: routine.id)
            return Dictionary(uniqueKeysWithValues: schedule.map { (String($0.weekday), $0.dayType.rawValue) })
        }
        var result: [Int: ScheduledDayType] = [:]
        for (weekday, type) in stored ?? [:] {
            if let day = Int(weekday), let dayType = ScheduledDayType(rawValue: type) { result[day] = dayType }
        }
        return result
    }

    func isRestDay(_ date: Date, in types: [Int: ScheduledDayType]) -> Bool {
        types[Calendar.current.component(.weekday, from: date)] == .rest
    }
}
