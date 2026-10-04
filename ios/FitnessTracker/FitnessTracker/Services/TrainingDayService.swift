import Foundation

/// What each weekday holds in the active split - used by Nutrition (no
/// Preworkout meal on a rest day) and the workout widget. Remembered for
/// offline use.
struct TrainingDayService {
    /// One weekday's plan: its type and a name to show for it.
    struct DayPlan: Codable, Equatable {
        let type: ScheduledDayType
        /// "Upper A" for a workout, "Incline Walk" for active rest, "Rest day".
        let title: String
    }

    private let routineRepository = RoutineRepository()
    private let scheduleRepository = WeeklyScheduleRepository()

    /// Weekday (1 = Sunday ... 7) to plan. Empty when there's no active
    /// split, in which case nothing should be treated as a rest day.
    func weekPlans() async -> [Int: DayPlan] {
        let stored: [String: DayPlan]? = try? await cachedRead(key: "week-plans") {
            guard let routine = try await routineRepository.fetchActiveRoutine() else { return [String: DayPlan]() }
            let schedule = try await scheduleRepository.fetchSchedule(routineId: routine.id)
            let days = (try? await routineRepository.fetchDays(routineId: routine.id)) ?? []
            var plans: [String: DayPlan] = [:]
            for day in schedule {
                let title: String
                switch day.dayType {
                case .workout:
                    title = days.first { $0.id == day.routineDayId }?.label ?? "Workout"
                case .activeRest:
                    title = day.cardioType?.displayName ?? "Active rest"
                case .rest:
                    title = "Rest day"
                }
                plans[String(day.weekday)] = DayPlan(type: day.dayType, title: title)
            }
            return plans
        }
        var result: [Int: DayPlan] = [:]
        for (weekday, plan) in stored ?? [:] {
            if let day = Int(weekday) { result[day] = plan }
        }
        return result
    }

    func weekdayTypes() async -> [Int: ScheduledDayType] {
        await weekPlans().mapValues(\.type)
    }

    func plan(for date: Date, in plans: [Int: DayPlan]) -> DayPlan? {
        plans[Calendar.current.component(.weekday, from: date)]
    }

    func isRestDay(_ date: Date, in types: [Int: ScheduledDayType]) -> Bool {
        types[Calendar.current.component(.weekday, from: date)] == .rest
    }
}
