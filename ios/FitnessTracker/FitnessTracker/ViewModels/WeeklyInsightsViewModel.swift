import Combine
import Foundation

/// Volume/cardio-session only - calorie/step/weight averages and their
/// debts live in their own published properties below instead
/// (`avgCaloriesPerDay`/`nutritionDebt`, `avgStepsPerDay`/`stepsDebt`,
/// `avgWeightThisWeek`/`avgWeightLastWeek`).
struct WeeklySummary {
    let weeklyVolumeKg: Double?
    let cardioSessionsCompleted: Int
}

/// One calendar day's step count in the Monday-Sunday breakdown. `steps` is
/// nil for a day with no synced data yet - either it hasn't happened, or
/// today's count just hasn't come in - rather than a definite zero.
struct DailyStepEntry: Identifiable {
    let date: Date
    let steps: Int?
    var id: Date { date }
}

/// One calendar day's value for a single nutrition macro (calories, or one
/// of protein/carbs/fat) in the Monday-Sunday breakdown - same "nil means
/// not happened/not synced yet" convention as `DailyStepEntry`. Generic
/// over which macro so the Nutrition section's picker can reuse one
/// breakdown view/view-model shape for whichever one is selected.
struct DailyMacroEntry: Identifiable {
    let date: Date
    let value: Double?
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

/// Tracks progress toward the step target over the selected Monday-Sunday
/// week - only ever computed for the current week (see `load()`), since
/// "what do I need today to hit this week's target" is meaningless for a
/// completed past week. Today always counts as one of the "remaining" days
/// rather than a "completed" one, since its step count is still
/// accumulating live - the catch-up number is "how many steps, starting
/// from right now through Sunday, to land the week on target."
struct StepsDebt {
    let remainingDays: Int
    let stepsBehindPace: Int
    let requiredPerDayForRest: Int
}

/// Same "debt" framing as `StepsDebt`, applied to calories or one macro -
/// given what's been logged across this week's completed days (today's
/// count, if anything's already been logged, folded in too, same as
/// steps), how much this would need to average per day for the rest of the
/// week to land the week on `target`. Unlike steps (always "more is fine"),
/// a low `requiredPerDayForRest` can mean either "you've already hit your
/// share" or "ease off, you're already over" - the raw number doesn't carry
/// that judgment on its own, which is why the UI states it plainly rather
/// than framing it as "ahead/behind pace" the way steps does.
struct MacroDebt {
    let target: Double
    let remainingDays: Int
    let requiredPerDayForRest: Double
}

struct NutritionDebtSummary {
    let protein: MacroDebt?
    let carbs: MacroDebt?
    let fat: MacroDebt?

    var hasAny: Bool {
        protein != nil || carbs != nil || fat != nil
    }
}

@MainActor
final class WeeklyInsightsViewModel: ObservableObject {
    @Published var goal: UserGoal?
    @Published var summary: WeeklySummary?
    /// This week's raw weigh-ins, oldest-first - powers the Weight
    /// section's chart.
    @Published var weekWeights: [BodyWeightLog] = []
    @Published var avgWeightThisWeek: Double?
    @Published var avgWeightLastWeek: Double?
    /// How many weigh-ins feeding `avgWeightThisWeek` were dropped as a
    /// post-off-plan water-weight bump - see
    /// `OffPlanWeightAdvisor.excludingBumpDates`. The Weight section shows
    /// a caption under the headline when this is nonzero.
    @Published var avgWeightThisWeekExcludedBumpDays = 0
    /// Total change since `goal.startingWeightKg` - only populated for the
    /// live current week (see its own computation in `load()`).
    @Published var totalPhaseWeightChangeKg: Double?
    @Published var dailySteps: [DailyStepEntry] = []
    /// The selected week's average steps/day (over days elapsed so far, not
    /// padded with zeros for days not yet happened) - alongside
    /// `dailySteps` for the breakdown, and `stepsDebt` for the current
    /// week's catch-up pace.
    @Published var avgStepsPerDay: Double?
    /// Only non-nil for the currently-selected week when it's also the
    /// live current week - see `StepsDebt`'s doc comment.
    @Published var stepsDebt: StepsDebt?
    /// This week's calorie average and day-by-day breakdown - moved here
    /// from the old standalone Weekly Log screen (one row per week, now
    /// retired) since this is where a given week's "why" detail lives.
    @Published var avgCaloriesPerDay: Double?
    @Published var avgProteinPerDay: Double?
    @Published var avgCarbsPerDay: Double?
    @Published var avgFatPerDay: Double?
    @Published var dailyCalories: [DailyMacroEntry] = []
    @Published var dailyProtein: [DailyMacroEntry] = []
    @Published var dailyCarbs: [DailyMacroEntry] = []
    @Published var dailyFat: [DailyMacroEntry] = []
    /// This week's average ml/day, over days with at least one log - same
    /// "only counts days that were actually logged" convention as
    /// `avgCaloriesPerDay`, not padded with zeros for days nothing was
    /// logged.
    @Published var avgWaterMlPerDay: Double?
    /// Only non-nil when the selected week is the live current week - same
    /// "what do I need today" reasoning as `stepsDebt`.
    @Published var nutritionDebt: NutritionDebtSummary?
    @Published var maintenanceInsight: MaintenanceInsight?
    @Published var completedNutritionDays = 0
    @Published var completedDaysInSelectedWeek = 0
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
    /// this week; `selectWeek(startingAt:)` is the only way to change it.
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
    private let waterRepository = WaterRepository()

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

    /// Jumps straight to an arbitrary week (picked from the week-picker
    /// dropdown, the only way to change weeks) - `weekStart` is normalized
    /// to its Monday regardless of what date within that week is passed in.
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
        // the week-picker dropdown never offers a week past the current
        // one). The cap is
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
        async let nutritionLogsResult = try? nutritionRepository.fetchDailyTotals(from: weekStart, to: sundayThisWeek)
        async let waterLogsResult = try? waterRepository.fetchLogs(from: weekStart, to: sundayThisWeek)
        async let cardioHistoryResult = try? cardioSessionRepository.fetchHistory(from: weekStart, to: sundayThisWeek)
        async let weightsResult = try? bodyWeightRepository.fetchRange(from: weekStart, to: sundayThisWeek)
        // For the week-over-week average comparison below - the week
        // immediately before whichever week is selected, not necessarily
        // "last calendar week" if you're paging through history.
        async let lastWeekWeightsResult: [BodyWeightLog] = {
            let start = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
            let end = calendar.date(byAdding: .day, value: -1, to: weekStart) ?? weekStart
            return (try? await bodyWeightRepository.fetchRange(from: start, to: end)) ?? []
        }()
        // The single most recent weigh-in overall (not scoped to any
        // week) - what "total change this phase" is measured against.
        async let latestOverallWeightResult = try? bodyWeightRepository.fetchHistory(limit: 1)
        // Covers the last couple of days of the prior week too, so a
        // late-week off-plan flag's bump window is still caught when it
        // spills into this week's first day or two.
        async let lastWeekCheckinsResult: [DailyCheckin] = {
            let start = calendar.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart
            let end = calendar.date(byAdding: .day, value: -1, to: weekStart) ?? weekStart
            return (try? await dailyCheckinRepository.fetchRange(from: start, to: end)) ?? []
        }()
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
        let preferences = await preferencesResult ?? nil
        let cardioExclusionEnabled = preferences?.cardioStepExclusionEnabled ?? false
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
        let waterLogs = await waterLogsResult ?? []
        let cardioHistory = await cardioHistoryResult ?? []
        let weights = await weightsResult ?? []
        let lastWeekWeights = await lastWeekWeightsResult
        let latestOverallWeight = (await latestOverallWeightResult ?? []).first
        let latestEstimate = await latestEstimateResult ?? nil
        let weekWorkouts = await weekWorkoutsResult ?? []
        let weekCheckins = await weekCheckinsResult ?? []
        let lastWeekCheckins = await lastWeekCheckinsResult
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

        let nutritionByDate = Dictionary(uniqueKeysWithValues: nutritionLogs.map { ($0.date, $0) })
        func dailyMacroBuilder(_ keyPath: KeyPath<NutritionLog, Double>) -> [DailyMacroEntry] {
            var entries: [DailyMacroEntry] = []
            for offset in 0..<7 {
                let date = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
                let value = nutritionByDate[DateFormatting.isoDate(date)]?[keyPath: keyPath]
                entries.append(DailyMacroEntry(date: date, value: offset <= completedDays ? value : nil))
            }
            return entries
        }
        let dailyCaloriesBuilder = dailyMacroBuilder(\.calories)
        let dailyProteinBuilder = dailyMacroBuilder(\.proteinG)
        let dailyCarbsBuilder = dailyMacroBuilder(\.carbsG)
        let dailyFatBuilder = dailyMacroBuilder(\.fatG)

        let isThisWeekCurrent = weekStart == Self.mondayOfWeek(containing: Date())

        // Averaged over days that have actually FINISHED, not today's
        // still-in-progress count - a live partial day mixed into the same
        // average as completed ones understates how the completed days
        // actually went (a 169-step Saturday morning dragging down what
        // was otherwise a strong week) without being a real "today" number
        // either. `completedDays` is 7 for any past week (the whole week
        // has finished), so this is unchanged there - only the live
        // current week ever excludes today from this average. Steps debt
        // is the one that answers "am I on track today," using today's
        // partial count on purpose - this figure answers "how did the
        // week go so far," which today can't answer yet.
        let resolvedAvgSteps = average(dailyStepsBuilder.prefix(completedDays).compactMap { $0.steps.map(Double.init) })

        // Only meaningful for the live current week - see `StepsDebt`'s doc
        // comment.
        let resolvedStepsDebt: StepsDebt? = {
            guard isThisWeekCurrent, completedDays > 0, let stepTarget = resolvedGoal?.stepTarget else { return nil }
            var stepsBanked = 0
            for offset in 0..<completedDays {
                let date = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
                stepsBanked += weekStepsByDate[DateFormatting.isoDate(date)] ?? 0
            }
            // Today's live count (if anything's synced yet) is folded back
            // in even though it's not one of the "completed" days above -
            // the debt/pace numbers exist to answer "am I on track *right
            // now*."
            stepsBanked += weekStepsByDate[DateFormatting.isoDate(today)] ?? 0
            let remainingDays = 7 - completedDays
            let stepsBehindPace = stepsBanked - stepTarget * completedDays
            let requiredPerDayForRest = remainingDays > 0
                ? max(0, (stepTarget * 7 - stepsBanked + remainingDays - 1) / remainingDays)
                : 0
            return StepsDebt(remainingDays: remainingDays, stepsBehindPace: stepsBehindPace, requiredPerDayForRest: requiredPerDayForRest)
        }()

        // Only meaningful for the live current week - see
        // `NutritionDebtSummary`'s doc comment.
        let resolvedNutritionDebt: NutritionDebtSummary? = {
            guard isThisWeekCurrent, completedDays > 0 else { return nil }
            func macroDebt(target: Double?, keyPath: KeyPath<NutritionLog, Double>) -> MacroDebt? {
                guard let target, target > 0 else { return nil }
                var completedTotal = 0.0
                for offset in 0..<completedDays {
                    let date = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
                    if let log = nutritionByDate[DateFormatting.isoDate(date)] {
                        completedTotal += log[keyPath: keyPath]
                    }
                }
                let todaysSoFar = nutritionByDate[DateFormatting.isoDate(today)]?[keyPath: keyPath] ?? 0
                let banked = completedTotal + todaysSoFar
                let remainingDays = 7 - completedDays
                let requiredPerDayForRest = remainingDays > 0 ? max(0, (target * 7 - banked) / Double(remainingDays)) : 0
                return MacroDebt(target: target, remainingDays: remainingDays, requiredPerDayForRest: requiredPerDayForRest)
            }
            return NutritionDebtSummary(
                protein: macroDebt(target: resolvedGoal?.proteinGTarget, keyPath: \.proteinG),
                carbs: macroDebt(target: resolvedGoal?.carbsGTarget, keyPath: \.carbsG),
                fat: macroDebt(target: resolvedGoal?.fatGTarget, keyPath: \.fatG)
            )
        }()

        // Only feeds the Maintenance Calories card below (current week
        // only) - the avg-calories-this-week display itself moved to
        // Weekly Log, so this no longer needs to be part of `summary`.
        let avgCalories = average(nutritionLogs.map(\.calories))
        let todayISO = DateFormatting.isoDate(today)
        let completedNutritionLogs = nutritionLogs.filter { $0.date < todayISO }
        let loggedCompletedNutritionDays = Set(completedNutritionLogs.map(\.date)).count
        let minimumNutritionDays = max(3, Int(ceil(Double(completedDays) * 0.8)))
        let avgProtein = average(nutritionLogs.map(\.proteinG))
        let avgCarbs = average(nutritionLogs.map(\.carbsG))
        let avgFat = average(nutritionLogs.map(\.fatG))

        // Summed per day first, then averaged across days with at least one
        // log - several logs on the same day (a hydroflask, a pint, a
        // custom amount) are one day's total, not several separate readings.
        let waterMlByDate = Dictionary(grouping: waterLogs, by: \.date).mapValues { $0.reduce(0) { $0 + $1.amountMl } }
        let avgWaterMl = average(waterMlByDate.values.map(Double.init))

        // Already range-filtered server-side (`fetchHistory(from:to:)`), so
        // no client-side date filter is needed here.
        let cardioSessionsCompleted = cardioHistory.filter { $0.endedAt != nil }.count

        // Trend-facing only - `weekWeights` below (the chart) still shows
        // every raw reading, bump included; only these averages, and the
        // pace verdict they feed, drop a bump-window reading.
        let allNearbyCheckins = weekCheckins + lastWeekCheckins
        let (cleanedWeekWeights, weekExcludedCount) = OffPlanWeightAdvisor.excludingBumpDates(from: weights, checkins: allNearbyCheckins)
        let (cleanedLastWeekWeights, _) = OffPlanWeightAdvisor.excludingBumpDates(from: lastWeekWeights, checkins: allNearbyCheckins)
        let resolvedAvgWeightThisWeek = average(cleanedWeekWeights.map(\.weightKg))
        let resolvedAvgWeightLastWeek = average(cleanedLastWeekWeights.map(\.weightKg))

        // Total change since the phase began - only meaningful for the live
        // current week (same reasoning as `resolvedMaintenanceInsight`
        // below), and always against the single most recent weigh-in
        // overall rather than anything scoped to the selected week, since
        // "how much have I lost this phase" doesn't reset week to week.
        let resolvedTotalPhaseChange: Double? = {
            guard isThisWeekCurrent,
                  let startingWeightKg = resolvedGoal?.startingWeightKg,
                  let latestWeightKg = latestOverallWeight?.weightKg
            else { return nil }
            return latestWeightKg - startingWeightKg
        }()

        // Only meaningful for the current week - it's a real-time "at your
        // recent rate" recommendation, not a historical figure a past week
        // can be judged against. Checked against `weekStart` (this call's
        // own target week, declared above), not the live `isCurrentWeek`,
        // which could have already moved on to a different week by the
        // time this resolves.
        let resolvedMaintenanceInsight: MaintenanceInsight? = {
            guard isThisWeekCurrent,
                  completedDays >= 3,
                  loggedCompletedNutritionDays >= minimumNutritionDays,
                  let estimate = latestEstimate,
                  estimate.loggedDaysInWindow >= Int(ceil(Double(estimate.windowDays) * 5.0 / 7.0)),
                  let completedDayAverage = average(completedNutritionLogs.map(\.calories))
            else { return nil }
            let impliedWeeklyChangeKg = (completedDayAverage - estimate.estimatedTDEE) * 7 / AdaptiveTDEEEngine.kcalPerKg
            return MaintenanceInsight(
                estimatedTDEE: estimate.estimatedTDEE,
                avgCaloriesPerDay: completedDayAverage,
                impliedWeeklyChangeKg: impliedWeeklyChangeKg
            )
        }()

        // A newer load has since started (fast prev/next flicking through
        // weeks) - discard these now-stale results rather than let them
        // land after, and overwrite, what the newer load already committed.
        guard generation == loadGeneration else { return }

        goal = resolvedGoal
        dailySteps = dailyStepsBuilder
        avgStepsPerDay = resolvedAvgSteps
        stepsDebt = resolvedStepsDebt
        dailyCalories = dailyCaloriesBuilder
        dailyProtein = dailyProteinBuilder
        dailyCarbs = dailyCarbsBuilder
        dailyFat = dailyFatBuilder
        avgCaloriesPerDay = avgCalories
        avgProteinPerDay = avgProtein
        avgCarbsPerDay = avgCarbs
        avgFatPerDay = avgFat
        avgWaterMlPerDay = avgWaterMl
        nutritionDebt = resolvedNutritionDebt
        weekWeights = weights
        avgWeightThisWeek = resolvedAvgWeightThisWeek
        avgWeightLastWeek = resolvedAvgWeightLastWeek
        avgWeightThisWeekExcludedBumpDays = weekExcludedCount
        totalPhaseWeightChangeKg = resolvedTotalPhaseChange
        summary = WeeklySummary(
            weeklyVolumeKg: resolvedVolumeKg,
            cardioSessionsCompleted: cardioSessionsCompleted
        )
        maintenanceInsight = resolvedMaintenanceInsight
        completedNutritionDays = loggedCompletedNutritionDays
        completedDaysInSelectedWeek = completedDays
        weeklyAdherence = buildWeeklyAdherence(
            weekStart: weekStart,
            nutritionLogs: nutritionLogs,
            stepLogs: weekStepLogs,
            workouts: weekWorkouts,
            checkins: weekCheckins,
            cardioExclusionEnabled: cardioExclusionEnabled,
            excludedStepsByDate: excludedStepsByDate,
            allGoals: allGoals,
            elapsedDaysCount: isThisWeekCurrent ? min(7, completedDays + 1) : 7
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
        allGoals: [UserGoal],
        elapsedDaysCount: Int
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
            requiredSessionsPerWeek: requiredSessions,
            elapsedDaysCount: elapsedDaysCount
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

        async let nutritionResult = try? nutritionRepository.fetchDailyTotals(from: historyStart, to: historyEnd)
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
                allGoals: allGoals,
                elapsedDaysCount: 7
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
