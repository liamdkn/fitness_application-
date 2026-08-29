import Combine
import Foundation

struct WeeklySummary {
    let weeklyVolumeKg: Double?
    let avgStepsPerDay: Int?
    let avgCaloriesPerLoggedDay: Double?
    let avgProteinG: Double?
    let avgCarbsG: Double?
    let avgFatG: Double?
    let cardioSessionsCompleted: Int
    let weightChangeThisWeekKg: Double?
}

/// One calendar day's step count in the Monday-Sunday breakdown. `steps` is
/// nil for a day with no synced data yet - either it hasn't happened, or
/// today's count just hasn't come in - rather than a definite zero.
struct DailyStepEntry: Identifiable {
    let date: Date
    let steps: Int?
    var id: Date { date }
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
    @Published var dailySteps: [DailyStepEntry] = []
    @Published var stepsDebt: StepsDebt?
    @Published var maintenanceInsight: MaintenanceInsight?
    @Published var weeklyAdherence: WeeklyAdherenceScore?
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
    private let dailyCheckinRepository = DailyCheckinRepository()

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
        let sundayThisWeek = calendar.date(byAdding: .day, value: 6, to: mondayThisWeek) ?? mondayThisWeek

        // Covers both the locale week (adherence) and the Monday-anchored
        // window (steps debt/breakdown) in one fetch, whichever starts earlier.
        let exclusionRangeStart = min(weekStart, mondayThisWeek)

        async let goalResult = try? goalsRepository.fetchCurrentGoal()
        async let volumeResult = try? workoutRepository.fetchWeeklyVolumeKg()
        async let stepLogsResult = try? healthRepository.fetchStepLogs(from: weekStart, to: now)
        // Whole Monday-Sunday week in one fetch - both the day-by-day
        // breakdown and the avg/debt numbers (Monday..yesterday only) are
        // derived from this single source, so they can never disagree with
        // each other the way two separately-ranged queries could.
        async let weekStepLogsResult = try? healthRepository.fetchStepLogs(from: mondayThisWeek, to: sundayThisWeek)
        async let nutritionLogsResult = try? nutritionRepository.fetchRange(from: weekStart, to: now)
        async let cardioHistoryResult = try? cardioSessionRepository.fetchHistory(limit: 50)
        async let weightsResult = try? bodyWeightRepository.fetchRecent(days: 14)
        async let latestEstimateResult = try? tdeeEstimateRepository.fetchLatest()
        async let preferencesResult = try? preferencesRepository.fetch()
        async let cardioStepSessionsResult = try? cardioStepSessionRepository.fetchSessions(from: exclusionRangeStart, to: now)
        async let weekWorkoutsResult = try? workoutRepository.fetchWorkouts(from: weekStart, to: now)
        async let weekCheckinsResult = try? dailyCheckinRepository.fetchRange(from: weekStart, to: now)

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

        func adjustedStepsByDate(_ logs: [StepLogRecord]) -> [String: Int] {
            var result: [String: Int] = [:]
            for log in logs {
                result[log.date] = cardioExclusionEnabled ? max(log.stepCount - (excludedStepsByDate[log.date] ?? 0), 0) : log.stepCount
            }
            return result
        }

        let stepLogs = await stepLogsResult ?? []
        let nutritionLogs = await nutritionLogsResult ?? []
        let cardioHistory = await cardioHistoryResult ?? []
        let weights = await weightsResult ?? []
        let latestEstimate = await latestEstimateResult ?? nil

        // Today never counts as "completed" - its step count is still
        // accumulating live, so both the breakdown and the pace numbers
        // treat it as still in progress rather than a finished (or missed)
        // day.
        let weekStepsByDate = adjustedStepsByDate(await weekStepLogsResult ?? [])
        let completedDays = daysSinceMonday
        var dailyStepsBuilder: [DailyStepEntry] = []
        var actualStepsCompleted = 0
        for offset in 0..<7 {
            let date = calendar.date(byAdding: .day, value: offset, to: mondayThisWeek) ?? mondayThisWeek
            let steps = weekStepsByDate[DateFormatting.isoDate(date)]
            // Today (offset == completedDays) still shows its live count if
            // any has synced - only days strictly in the future are blank.
            dailyStepsBuilder.append(DailyStepEntry(date: date, steps: offset <= completedDays ? steps : nil))
            if offset < completedDays {
                actualStepsCompleted += steps ?? 0
            }
        }
        dailySteps = dailyStepsBuilder
        let avgSteps = completedDays > 0 ? actualStepsCompleted / completedDays : nil

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
            avgStepsPerDay: avgSteps,
            avgCaloriesPerLoggedDay: avgCalories,
            avgProteinG: avgProtein,
            avgCarbsG: avgCarbs,
            avgFatG: avgFat,
            cardioSessionsCompleted: cardioSessionsCompleted,
            weightChangeThisWeekKg: weightChange
        )

        // Built from the exact same `actualStepsCompleted`/`completedDays`
        // as `avgSteps` above, so the debt and the average can never tell a
        // contradictory story (e.g. "ahead of your daily average" while
        // also "behind pace") the way two separately-computed numbers could.
        if let stepTarget = goal?.stepTarget {
            let remainingDays = 7 - completedDays
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

        let weekWorkouts = await weekWorkoutsResult ?? []
        let weekCheckins = await weekCheckinsResult ?? []
        weeklyAdherence = buildWeeklyAdherence(
            weekStart: weekStart,
            nutritionLogs: nutritionLogs,
            stepLogs: stepLogs,
            workouts: weekWorkouts,
            checkins: weekCheckins,
            cardioExclusionEnabled: cardioExclusionEnabled,
            excludedStepsByDate: excludedStepsByDate
        )
    }

    /// One `DailyAdherenceScore` per day of the (locale) week, Sunday/Monday
    /// through today-or-later, rolled up into a `WeeklyAdherenceScore` -
    /// a day past today simply has no data yet, which the engine already
    /// treats as "excluded" rather than a miss.
    private func buildWeeklyAdherence(
        weekStart: Date,
        nutritionLogs: [NutritionLog],
        stepLogs: [StepLogRecord],
        workouts: [Workout],
        checkins: [DailyCheckin],
        cardioExclusionEnabled: Bool,
        excludedStepsByDate: [String: Int]
    ) -> WeeklyAdherenceScore? {
        guard goal != nil else { return nil }
        let calendar = Calendar.current

        let nutritionByDate = Dictionary(uniqueKeysWithValues: nutritionLogs.map { ($0.date, $0) })
        let checkinByDate = Dictionary(uniqueKeysWithValues: checkins.map { ($0.checkinDate, $0) })
        let stepsByDate: [String: Int] = stepLogs.reduce(into: [:]) { result, log in
            let raw = log.stepCount
            result[log.date] = cardioExclusionEnabled ? max(raw - (excludedStepsByDate[log.date] ?? 0), 0) : raw
        }
        let workoutDates = Set(workouts.map { calendar.startOfDay(for: $0.performedAt) })

        var dailyScores: [DailyAdherenceScore] = []
        var sessionsCompleted = 0
        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { continue }
            let isoDate = DateFormatting.isoDate(date)
            let didWorkout = workoutDates.contains(calendar.startOfDay(for: date))
            if didWorkout { sessionsCompleted += 1 }
            dailyScores.append(AdherenceScoreEngine.dailyScore(
                date: date,
                goal: goal,
                nutrition: nutritionByDate[isoDate],
                steps: stepsByDate[isoDate],
                didWorkout: didWorkout,
                isRestDay: checkinByDate[isoDate]?.isRestDay
            ))
        }

        let requiredSessions = goal?.strengthSessionsPerWeek.map { $0 - (goal?.strengthOptionalSessions ?? 0) }
        return AdherenceScoreEngine.weeklyScore(
            dailyScores: dailyScores,
            sessionsCompleted: sessionsCompleted,
            requiredSessionsPerWeek: requiredSessions
        )
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
