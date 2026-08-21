import Combine
import Foundation

struct WeeklySummary {
    let weeklyVolumeKg: Double?
    let avgStepsPerLoggedDay: Int?
    let avgCaloriesPerLoggedDay: Double?
    let avgProteinG: Double?
    let avgCarbsG: Double?
    let avgFatG: Double?
    let cardioSessionsCompleted: Int
    let weightChangeThisWeekKg: Double?
}

/// Tracks progress toward a 10k-steps-a-day average over a strict
/// Monday-Sunday week (independent of the device's locale/first-weekday
/// setting, unlike the rest of this screen's "this week" aggregations).
/// Today always counts as one of the "remaining" days rather than a
/// "completed" one, since its step count is still accumulating live -
/// the catch-up number is always "how many steps, starting from right now
/// through Sunday, to land the week on target."
struct StepsDebt {
    let completedDays: Int
    let remainingDays: Int
    let stepsBehindPace: Int
    let requiredPerDayForRest: Int
}

/// A calorie surplus/deficit reading against the adaptive-TDEE estimate,
/// translated into a plain-English "at that rate you're on pace for X"
/// statement - the same kcal-per-kg constant AdaptiveTDEEEngine uses for its
/// own recommendation, applied here in the other direction (surplus -> rate
/// rather than rate -> recommended calories).
struct MaintenanceInsight {
    let estimatedTDEE: Double
    let avgCaloriesPerDay: Double
    let impliedWeeklyChangeKg: Double

    var surplusOrDeficit: Double { avgCaloriesPerDay - estimatedTDEE }
}

@MainActor
final class WeeklyInsightsViewModel: ObservableObject {
    @Published var goal: UserGoal?
    @Published var summary: WeeklySummary?
    @Published var stepsDebt: StepsDebt?
    @Published var maintenanceInsight: MaintenanceInsight?
    @Published var errorMessage: String?
    @Published var isLoading = false

    private let goalsRepository = GoalsRepository()
    private let nutritionRepository = NutritionRepository()
    private let healthRepository = HealthRepository()
    private let workoutRepository = WorkoutRepository()
    private let bodyWeightRepository = BodyWeightRepository()
    private let cardioSessionRepository = CardioSessionRepository()
    private let cardioStepSessionRepository = CardioStepSessionRepository()
    private let preferencesRepository = UserPreferencesRepository()
    private let tdeeEstimateRepository = TDEEEstimateRepository()

    func load() async {
        isLoading = true
        defer { isLoading = false }

        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let now = Date()

        // Strict Monday-anchored week for the steps-debt calculation, kept
        // independent of the locale-dependent `weekStart` above (which may
        // not start on Monday depending on the device's first-weekday
        // setting). `.weekday` is always 1=Sunday...7=Saturday regardless of
        // that setting, so this arithmetic is locale-proof.
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let daysSinceMonday = (weekday + 5) % 7
        let mondayThisWeek = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today

        // Covers both the locale week (avg steps/day) and the Monday-anchored
        // window (steps debt) in one fetch, whichever starts earlier.
        let exclusionRangeStart = min(weekStart, mondayThisWeek)

        async let goalResult = try? goalsRepository.fetchCurrentGoal()
        async let volumeResult = try? workoutRepository.fetchWeeklyVolumeKg()
        async let stepLogsResult = try? healthRepository.fetchStepLogs(from: weekStart, to: now)
        // On Monday, `yesterday` falls before `mondayThisWeek`, making this
        // an empty (from > to) range - which correctly yields zero
        // completed days rather than needing a special case.
        async let debtStepLogsResult = try? healthRepository.fetchStepLogs(from: mondayThisWeek, to: yesterday)
        async let nutritionLogsResult = try? nutritionRepository.fetchRange(from: weekStart, to: now)
        async let cardioHistoryResult = try? cardioSessionRepository.fetchHistory(limit: 50)
        async let weightsResult = try? bodyWeightRepository.fetchRecent(days: 14)
        async let latestEstimateResult = try? tdeeEstimateRepository.fetchLatest()
        async let preferencesResult = try? preferencesRepository.fetch()
        async let cardioStepSessionsResult = try? cardioStepSessionRepository.fetchSessions(from: exclusionRangeStart, to: now)

        goal = await goalResult ?? nil

        // Mirrors the Dashboard's "exclude machine-counted cardio steps"
        // adjustment (DashboardView's `displaySteps`), which otherwise only
        // applied to today's step count - without this, a week that
        // included cardio sessions would show a higher (raw) step average
        // here than what the Dashboard displays day to day, throwing off
        // the steps-debt pace calculation.
        let cardioExclusionEnabled = (await preferencesResult ?? nil)?.cardioStepExclusionEnabled ?? false
        let cardioStepSessions = await cardioStepSessionsResult ?? []
        let excludedStepsByDate = Dictionary(grouping: cardioStepSessions, by: \.date)
            .mapValues { $0.reduce(0) { $0 + $1.stepsDelta } }

        func adjusted(_ logs: [StepLogRecord]) -> [Int] {
            guard cardioExclusionEnabled else { return logs.map(\.stepCount) }
            return logs.map { max($0.stepCount - (excludedStepsByDate[$0.date] ?? 0), 0) }
        }

        let stepLogs = await stepLogsResult ?? []
        let nutritionLogs = await nutritionLogsResult ?? []
        let cardioHistory = await cardioHistoryResult ?? []
        let weights = await weightsResult ?? []
        let latestEstimate = await latestEstimateResult ?? nil

        let adjustedStepLogs = adjusted(stepLogs)
        let avgSteps = adjustedStepLogs.isEmpty ? nil : adjustedStepLogs.reduce(0, +) / adjustedStepLogs.count
        let avgCalories = average(nutritionLogs.map(\.calories))
        let avgProtein = average(nutritionLogs.map(\.proteinG))
        let avgCarbs = average(nutritionLogs.map(\.carbsG))
        let avgFat = average(nutritionLogs.map(\.fatG))

        let cardioSessionsCompleted = cardioHistory.filter { session in
            session.endedAt != nil && session.startedAt >= weekStart
        }.count

        let weightsThisWeek = weights.filter { $0.loggedAt >= weekStart }
        let weightChange: Double? = {
            guard let first = weightsThisWeek.first, let last = weightsThisWeek.last, first.id != last.id else { return nil }
            return last.weightKg - first.weightKg
        }()

        summary = WeeklySummary(
            weeklyVolumeKg: await volumeResult ?? nil,
            avgStepsPerLoggedDay: avgSteps,
            avgCaloriesPerLoggedDay: avgCalories,
            avgProteinG: avgProtein,
            avgCarbsG: avgCarbs,
            avgFatG: avgFat,
            cardioSessionsCompleted: cardioSessionsCompleted,
            weightChangeThisWeekKg: weightChange
        )

        if let stepTarget = goal?.stepTarget {
            let debtStepLogs = await debtStepLogsResult ?? []
            let completedDays = daysSinceMonday
            let remainingDays = 7 - completedDays
            let actualStepsCompleted = adjusted(debtStepLogs).reduce(0, +)
            let stepsBehindPace = actualStepsCompleted - stepTarget * completedDays
            let requiredPerDayForRest = remainingDays > 0
                ? max(0, (stepTarget * 7 - actualStepsCompleted + remainingDays - 1) / remainingDays)
                : 0
            stepsDebt = StepsDebt(
                completedDays: completedDays,
                remainingDays: remainingDays,
                stepsBehindPace: stepsBehindPace,
                requiredPerDayForRest: requiredPerDayForRest
            )
        } else {
            stepsDebt = nil
        }

        if let estimatedTDEE = latestEstimate?.estimatedTDEE, let avgCalories {
            let impliedWeeklyChangeKg = (avgCalories - estimatedTDEE) * 7 / AdaptiveTDEEEngine.kcalPerKg
            maintenanceInsight = MaintenanceInsight(
                estimatedTDEE: estimatedTDEE,
                avgCaloriesPerDay: avgCalories,
                impliedWeeklyChangeKg: impliedWeeklyChangeKg
            )
        } else {
            maintenanceInsight = nil
        }
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
