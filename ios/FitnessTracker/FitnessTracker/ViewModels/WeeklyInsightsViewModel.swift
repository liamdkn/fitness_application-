import Combine
import Foundation

/// Volume/cardio-session/weight-change only - the avg calories/macros/steps
/// summary that used to live here moved to Weekly Log (one row per week, at
/// a glance for every week, not just the selected one), and steps/nutrition
/// debt moved to the Dashboard (an inherently current-week-only, "what do I
/// need today" concept, not a retrospective one).
struct WeeklySummary {
    let weeklyVolumeKg: Double?
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

/// One week's overall adherence score, used to plot a multi-week trend at
/// the top of Weekly Insights - `overall` is nil for a week that didn't
/// have enough logged data to score at all (same "not enough data" meaning
/// as `WeeklyAdherenceScore.overall`), which the chart just renders as a
/// gap rather than a zero.
struct WeeklyScorePoint: Identifiable {
    let weekStart: Date
    let overall: Double?
    var id: Date { weekStart }
}

@MainActor
final class WeeklyInsightsViewModel: ObservableObject {
    @Published var goal: UserGoal?
    @Published var summary: WeeklySummary?
    @Published var dailySteps: [DailyStepEntry] = []
    @Published var maintenanceInsight: MaintenanceInsight?
    @Published var weeklyAdherence: WeeklyAdherenceScore?
    /// Last `historyWeeksCount` weeks' overall scores, oldest first, ending
    /// at `selectedWeekStart` - see `loadScoreHistory`.
    @Published var scoreHistory: [WeeklyScorePoint] = []
    /// The weekly check-in survey (self-rated adherence/discipline/stress,
    /// biggest win, mood notes) filled in for the selected week, if any -
    /// shown alongside the objective adherence score so the two can be
    /// compared.
    @Published var weeklyCheckin: WeeklyCheckin?
    /// Monday of whichever week is currently being viewed - defaults to
    /// this week, but `goToPreviousWeek()`/`goToNextWeek()` can walk it
    /// back through history (never past the current week).
    @Published private(set) var selectedWeekStart = WeeklyInsightsViewModel.mondayOfWeek(containing: Date())
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
    private let weeklyCheckinRepository = WeeklyCheckinRepository()

    /// How many trailing weeks the trend chart covers.
    private let historyWeeksCount = 8

    /// Bumped at the start of every `load()` - flicking through weeks
    /// quickly starts a new load before an older one's network calls have
    /// returned, and without this an older, slower response could land
    /// after a newer one and overwrite it with the wrong week's data. Only
    /// the call that's still the most recent one when it finishes is
    /// allowed to commit its results.
    private var loadGeneration = 0

    /// The phase actually in effect on a given date - the latest
    /// `user_goals` row whose `effectiveFrom` is on or before that date.
    /// `allGoals` must already be sorted ascending by `effectiveFrom` (see
    /// `fetchPastGoals`) - this is pure client-side resolution, so a whole
    /// week (or the trailing-history trend's several weeks) can reuse one
    /// fetched list rather than a query per lookup. Point-in-time, not
    /// "whatever's active today": navigating to a past week, or a
    /// mid-phase nutrition-target adjustment since, shouldn't judge that
    /// week against a target that didn't exist yet when it happened.
    private func goalEffective(in allGoals: [UserGoal], asOf date: Date) -> UserGoal? {
        let isoDate = DateFormatting.isoDate(date)
        return allGoals.last { $0.effectiveFrom <= isoDate }
    }

    /// The whole screen is a strict Monday-Sunday week - see
    /// `DateFormatting.mondayOfWeek(containing:)`, shared with Weekly Log
    /// and the Dashboard's steps/nutrition debt so all three agree on
    /// where a week starts.
    static func mondayOfWeek(containing date: Date) -> Date {
        DateFormatting.mondayOfWeek(containing: date)
    }

    var isCurrentWeek: Bool {
        selectedWeekStart == Self.mondayOfWeek(containing: Date())
    }

    func goToPreviousWeek() {
        guard let newStart = Calendar.current.date(byAdding: .day, value: -7, to: selectedWeekStart) else { return }
        selectedWeekStart = newStart
        Task { await load() }
    }

    func goToNextWeek() {
        guard !isCurrentWeek else { return }
        guard let newStart = Calendar.current.date(byAdding: .day, value: 7, to: selectedWeekStart) else { return }
        selectedWeekStart = newStart
        Task { await load() }
    }

    /// Jumps straight to an arbitrary week (e.g. a row tapped in Weekly
    /// Log) rather than stepping through `goToPreviousWeek()` one week at a
    /// time - `weekStart` is normalized to its Monday regardless of what
    /// date within that week is passed in.
    func selectWeek(startingAt weekStart: Date) {
        selectedWeekStart = Self.mondayOfWeek(containing: weekStart)
        Task { await load() }
    }

    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        defer {
            // A newer load has since started and will clear this itself
            // when it finishes - don't clear the flag out from under it.
            if generation == loadGeneration { isLoading = false }
        }

        let calendar = Calendar.current
        let weekStart = selectedWeekStart
        let sundayThisWeek = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let today = calendar.startOfDay(for: Date())

        // How many of this week's days are fully in the past - 7 for any
        // week before this one, a partial count for the current week
        // (today itself is still "in progress" and never counts as
        // completed), 0 if this were somehow a future week (can't happen -
        // `goToNextWeek()` is capped at the current week). The cap is
        // `sundayThisWeek` plus one day, not `sundayThisWeek` itself -
        // Monday-to-Sunday is a 6-day difference in date-component terms,
        // so capping at the Sunday itself silently excluded Sunday from
        // every past week's count (6 completed days, not 7).
        let dayAfterSunday = calendar.date(byAdding: .day, value: 1, to: sundayThisWeek) ?? sundayThisWeek
        let daysElapsed = calendar.dateComponents([.day], from: weekStart, to: min(today, dayAfterSunday)).day ?? 0
        let completedDays = max(0, min(7, daysElapsed))

        async let pastGoalsResult = try? goalsRepository.fetchPastGoals(limit: 100)
        async let volumeResult = try? workoutRepository.fetchVolumeKg(from: weekStart, to: sundayThisWeek)
        // Whole Monday-Sunday week in one fetch, reused for both the
        // day-by-day breakdown and the weekly adherence score - a single
        // source for "this week's steps" means they can never disagree
        // with each other the way separately-ranged queries could.
        async let weekStepLogsResult = try? healthRepository.fetchStepLogs(from: weekStart, to: sundayThisWeek)
        async let nutritionLogsResult = try? nutritionRepository.fetchRange(from: weekStart, to: sundayThisWeek)
        async let cardioHistoryResult = try? cardioSessionRepository.fetchHistory(from: weekStart, to: sundayThisWeek)
        async let weightsResult = try? bodyWeightRepository.fetchRange(from: weekStart, to: sundayThisWeek)
        async let latestEstimateResult = try? tdeeEstimateRepository.fetchLatest()
        async let preferencesResult = try? preferencesRepository.fetch()
        async let cardioStepSessionsResult = try? cardioStepSessionRepository.fetchSessions(from: weekStart, to: sundayThisWeek)
        async let weekWorkoutsResult = try? workoutRepository.fetchWorkouts(from: weekStart, to: sundayThisWeek)
        async let weekCheckinsResult = try? dailyCheckinRepository.fetchRange(from: weekStart, to: sundayThisWeek)
        async let weeklyCheckinsResult = try? weeklyCheckinRepository.fetchRange(from: weekStart, to: sundayThisWeek)

        // Every result is resolved into a plain local first - nothing
        // touches a `@Published` property until the single generation
        // check below passes, so a stale, slower call from an earlier week
        // can never partially overwrite what a newer one already
        // committed (or is about to).
        let allGoals = (await pastGoalsResult ?? []).sorted { $0.effectiveFrom < $1.effectiveFrom }
        let resolvedGoal = goalEffective(in: allGoals, asOf: min(today, sundayThisWeek))

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

        let weekStepLogs = await weekStepLogsResult ?? []
        let nutritionLogs = await nutritionLogsResult ?? []
        let cardioHistory = await cardioHistoryResult ?? []
        let weights = await weightsResult ?? []
        let latestEstimate = await latestEstimateResult ?? nil
        let weekWorkouts = await weekWorkoutsResult ?? []
        let weekCheckins = await weekCheckinsResult ?? []
        let resolvedWeeklyCheckin = (await weeklyCheckinsResult ?? []).first
        let resolvedVolumeKg = await volumeResult ?? nil

        let weekStepsByDate = adjustedStepsByDate(weekStepLogs)
        var dailyStepsBuilder: [DailyStepEntry] = []
        for offset in 0..<7 {
            let date = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
            let steps = weekStepsByDate[DateFormatting.isoDate(date)]
            // Today (offset == completedDays, current week only) still
            // shows its live count if any has synced - only days strictly
            // in the future are blank.
            dailyStepsBuilder.append(DailyStepEntry(date: date, steps: offset <= completedDays ? steps : nil))
        }

        let isThisWeekCurrent = weekStart == Self.mondayOfWeek(containing: Date())

        // Only feeds the Maintenance Calories card below (current week
        // only) - the avg-calories-this-week display itself moved to
        // Weekly Log, so this no longer needs to be part of `summary`.
        let avgCalories = average(nutritionLogs.map(\.calories))

        // Already range-filtered server-side (`fetchHistory(from:to:)`), so
        // no client-side date filter is needed here.
        let cardioSessionsCompleted = cardioHistory.filter { $0.endedAt != nil }.count

        let weightChange: Double? = {
            guard let first = weights.first, let last = weights.last, first.id != last.id else { return nil }
            return last.weightKg - first.weightKg
        }()

        // Only meaningful for the current week - it's a real-time "at your
        // recent rate" recommendation, not a historical figure a past week
        // can be judged against. Checked against `weekStart` (this call's
        // own target week, declared above), not the live `isCurrentWeek`,
        // which could have already moved on to a different week by the
        // time this resolves.
        let resolvedMaintenanceInsight: MaintenanceInsight? = {
            guard isThisWeekCurrent, let estimatedTDEE = latestEstimate?.estimatedTDEE, let avgCalories else { return nil }
            let impliedWeeklyChangeKg = (avgCalories - estimatedTDEE) * 7 / AdaptiveTDEEEngine.kcalPerKg
            return MaintenanceInsight(
                estimatedTDEE: estimatedTDEE,
                avgCaloriesPerDay: avgCalories,
                impliedWeeklyChangeKg: impliedWeeklyChangeKg
            )
        }()

        // A newer load has since started (fast prev/next flicking through
        // weeks) - discard these now-stale results rather than let them
        // land after, and overwrite, what the newer load already committed.
        guard generation == loadGeneration else { return }

        goal = resolvedGoal
        dailySteps = dailyStepsBuilder
        summary = WeeklySummary(
            weeklyVolumeKg: resolvedVolumeKg,
            cardioSessionsCompleted: cardioSessionsCompleted,
            weightChangeThisWeekKg: weightChange
        )
        maintenanceInsight = resolvedMaintenanceInsight
        weeklyAdherence = buildWeeklyAdherence(
            weekStart: weekStart,
            nutritionLogs: nutritionLogs,
            stepLogs: weekStepLogs,
            workouts: weekWorkouts,
            checkins: weekCheckins,
            cardioExclusionEnabled: cardioExclusionEnabled,
            excludedStepsByDate: excludedStepsByDate,
            allGoals: allGoals
        )
        weeklyCheckin = resolvedWeeklyCheckin

        await loadScoreHistory(selectedWeekStart: weekStart, generation: generation, allGoals: allGoals)
    }

    /// One `DailyAdherenceScore` per day of the selected Monday-Sunday week,
    /// rolled up into a `WeeklyAdherenceScore` - a day with no data (past
    /// today in the current week, or never logged in a past week) simply
    /// scores nil per component, which the engine already treats as
    /// "excluded" rather than a miss.
    private func buildWeeklyAdherence(
        weekStart: Date,
        nutritionLogs: [NutritionLog],
        stepLogs: [StepLogRecord],
        workouts: [Workout],
        checkins: [DailyCheckin],
        cardioExclusionEnabled: Bool,
        excludedStepsByDate: [String: Int],
        allGoals: [UserGoal]
    ) -> WeeklyAdherenceScore? {
        let calendar = Calendar.current
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let weekGoal = goalEffective(in: allGoals, asOf: weekEnd)
        guard weekGoal != nil else { return nil }

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
                goal: goalEffective(in: allGoals, asOf: date),
                nutrition: nutritionByDate[isoDate],
                steps: stepsByDate[isoDate],
                didWorkout: didWorkout,
                isRestDay: checkinByDate[isoDate]?.isRestDay
            ))
        }

        let requiredSessions = weekGoal?.strengthSessionsPerWeek.map { $0 - (weekGoal?.strengthOptionalSessions ?? 0) }
        return AdherenceScoreEngine.weeklyScore(
            dailyScores: dailyScores,
            sessionsCompleted: sessionsCompleted,
            requiredSessionsPerWeek: requiredSessions
        )
    }

    /// Last `historyWeeksCount` weeks' overall scores (oldest first, ending
    /// at whichever week is currently selected) - powers the trend chart at
    /// the top of Weekly Insights. A single week's score can only answer
    /// "how was this week"; this is what answers "are we on the right
    /// trajectory," which the score alone can't. Fetches its own range
    /// independently of the rest of `load()` (a little overlap with the
    /// selected week's own fetch) so this stays simple and can't
    /// accidentally disagree with a differently-scoped query.
    private func loadScoreHistory(selectedWeekStart: Date, generation: Int, allGoals: [UserGoal]) async {
        guard !allGoals.isEmpty else {
            if generation == loadGeneration { scoreHistory = [] }
            return
        }
        let calendar = Calendar.current
        guard let historyStart = calendar.date(byAdding: .day, value: -7 * (historyWeeksCount - 1), to: selectedWeekStart),
              let historyEnd = calendar.date(byAdding: .day, value: 6, to: selectedWeekStart)
        else {
            if generation == loadGeneration { scoreHistory = [] }
            return
        }

        async let nutritionResult = try? nutritionRepository.fetchRange(from: historyStart, to: historyEnd)
        async let stepLogsResult = try? healthRepository.fetchStepLogs(from: historyStart, to: historyEnd)
        async let workoutsResult = try? workoutRepository.fetchWorkouts(from: historyStart, to: historyEnd)
        async let checkinsResult = try? dailyCheckinRepository.fetchRange(from: historyStart, to: historyEnd)
        async let preferencesResult = try? preferencesRepository.fetch()
        async let cardioStepSessionsResult = try? cardioStepSessionRepository.fetchSessions(from: historyStart, to: historyEnd)

        let nutritionLogs = await nutritionResult ?? []
        let stepLogs = await stepLogsResult ?? []
        let workouts = await workoutsResult ?? []
        let checkins = await checkinsResult ?? []
        let cardioExclusionEnabled = (await preferencesResult ?? nil)?.cardioStepExclusionEnabled ?? false
        let excludedStepsByDate = Dictionary(grouping: await cardioStepSessionsResult ?? [], by: \.date)
            .mapValues { $0.reduce(0) { $0 + $1.stepsDelta } }

        var points: [WeeklyScorePoint] = []
        for weekOffset in 0..<historyWeeksCount {
            guard let weekStart = calendar.date(byAdding: .day, value: -7 * (historyWeeksCount - 1 - weekOffset), to: selectedWeekStart),
                  let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)
            else { continue }

            let weekNutrition = nutritionLogs.filter { log in
                guard let date = DateFormatting.date(fromISODate: log.date) else { return false }
                return date >= weekStart && date <= weekEnd
            }
            let weekStepLogs = stepLogs.filter { log in
                guard let date = DateFormatting.date(fromISODate: log.date) else { return false }
                return date >= weekStart && date <= weekEnd
            }
            let weekWorkouts = workouts.filter { $0.performedAt >= weekStart && $0.performedAt <= weekEnd }
            let weekCheckins = checkins.filter { checkin in
                guard let date = DateFormatting.date(fromISODate: checkin.checkinDate) else { return false }
                return date >= weekStart && date <= weekEnd
            }

            let weeklyScore = buildWeeklyAdherence(
                weekStart: weekStart,
                nutritionLogs: weekNutrition,
                stepLogs: weekStepLogs,
                workouts: weekWorkouts,
                checkins: weekCheckins,
                cardioExclusionEnabled: cardioExclusionEnabled,
                excludedStepsByDate: excludedStepsByDate,
                allGoals: allGoals
            )
            points.append(WeeklyScorePoint(weekStart: weekStart, overall: weeklyScore?.overall))
        }
        guard generation == loadGeneration else { return }
        scoreHistory = points
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
