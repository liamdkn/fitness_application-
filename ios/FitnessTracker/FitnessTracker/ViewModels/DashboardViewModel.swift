import Combine
import Foundation

/// Tracks progress toward a 10k-steps-a-day average over the current
/// Monday-Sunday week - inherently current-week-only ("what do I need
/// today to hit this week's target" is meaningless for a completed past
/// week), which is why this lives on the Dashboard rather than Weekly
/// Insights. Today always counts as one of the "remaining" days rather
/// than a "completed" one, since its step count is still accumulating live
/// - the catch-up number is "how many steps, starting from right now
/// through Sunday, to land the week on target."
struct StepsDebt {
    let completedDays: Int
    let remainingDays: Int
    let stepsBehindPace: Int
    let requiredPerDayForRest: Int
}

/// Same "debt" framing as `StepsDebt`, applied to one nutrition macro -
/// given what's been logged across this week's completed days (today's
/// count, if anything's already been logged, folded in too, same as
/// steps), how much this macro would need to average per day for the rest
/// of the week to land the week on `target`. Unlike steps (always "more is
/// fine"), a low `requiredPerDayForRest` can mean either "you've already
/// hit your share" (calories/protein/carbs/fat all read this way when
/// under target) or "ease off, you're already over" - the raw number
/// doesn't carry that judgment on its own, which is why the UI states it
/// plainly rather than framing it as "ahead/behind pace" the way steps does.
struct MacroDebt {
    let target: Double
    let completedDays: Int
    let remainingDays: Int
    let requiredPerDayForRest: Double
}

struct NutritionDebtSummary {
    let calories: MacroDebt?
    let protein: MacroDebt?
    let carbs: MacroDebt?
    let fat: MacroDebt?

    var hasAny: Bool {
        calories != nil || protein != nil || carbs != nil || fat != nil
    }
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var goal: UserGoal?
    @Published var todayNutrition: NutritionLog?
    @Published var todaySteps: Int?
    @Published var lastNightSleepMinutes: Int?
    @Published var weeklyVolumeKg: Double?
    @Published var recentWeights: [BodyWeightLog] = []
    @Published var cardioExclusionEnabled = false
    @Published var cardioStepsExcludedToday = 0
    @Published var offPlanRecentInsight: OffPlanWeightAdvisor.RecentFlagInsight?
    @Published var offPlanHistoricalStat: OffPlanWeightAdvisor.HistoricalStat?
    /// This week's steps/nutrition debt - see `loadCurrentWeekDebts()`.
    /// Moved here from Weekly Insights: both are "what do I need today"
    /// figures, meaningless for any week but the current one.
    @Published var stepsDebt: StepsDebt?
    @Published var nutritionDebt: NutritionDebtSummary?
    @Published var errorMessage: String?
    @Published var isLoading = false

    private let goalsRepository = GoalsRepository()
    private let nutritionRepository = NutritionRepository()
    private let healthRepository = HealthRepository()
    private let workoutRepository = WorkoutRepository()
    private let bodyWeightRepository = BodyWeightRepository()
    private let preferencesRepository = UserPreferencesRepository()
    private let cardioStepSessionRepository = CardioStepSessionRepository()
    private let dailyCheckinRepository = DailyCheckinRepository()
    /// How far back `evaluateRecentFlag` gets to warm up the EWMA trend -
    /// independent of the Weight card's own W/2W/M/6M picker, so the note
    /// doesn't disappear just because someone's viewing the 1-week chart.
    private let offPlanTrendWindowDays = 30
    /// A few days is enough to catch "flagged Tue and Wed" - anything
    /// older than that is the historical stat's territory, not this note's.
    private let recentFlagLookbackDays = 3

    func load(date: Date = Date()) async {
        isLoading = true
        defer { isLoading = false }

        async let pastGoalsResult = try? goalsRepository.fetchPastGoals(limit: 100)
        async let nutritionResult = try? nutritionRepository.fetchLog(date: date)
        async let stepsResult = try? healthRepository.fetchStepLog(date: date)
        async let sleepResult = try? healthRepository.fetchSleepLog(date: date)
        async let volumeResult = try? workoutRepository.fetchWeeklyVolumeKg()
        async let preferencesResult = try? preferencesRepository.fetch()
        async let cardioSessionsResult = try? cardioStepSessionRepository.fetchSessions(date: date)

        // Point-in-time, not "whatever's active today" - the day-selector
        // chevrons let you look at a past day, and that day's calorie/
        // protein/etc. targets should reflect whatever phase was actually
        // active then, not today's (possibly since-adjusted) numbers.
        let allGoals = (await pastGoalsResult ?? []).sorted { $0.effectiveFrom < $1.effectiveFrom }
        let isoDate = DateFormatting.isoDate(date)
        goal = allGoals.last { $0.effectiveFrom <= isoDate }
        todayNutrition = await nutritionResult ?? nil
        todaySteps = (await stepsResult ?? nil)?.stepCount
        lastNightSleepMinutes = (await sleepResult ?? nil)?.totalSleepMinutes
        weeklyVolumeKg = await volumeResult ?? nil
        cardioExclusionEnabled = (await preferencesResult ?? nil)?.cardioStepExclusionEnabled ?? false
        let cardioSessions = await cardioSessionsResult ?? []
        cardioStepsExcludedToday = cardioSessions.reduce(0) { $0 + $1.stepsDelta }
    }

    /// The weight chart's own data, kept independent of `load()` - the
    /// chart isn't scoped to `selectedDate` the way calories/steps/sleep
    /// are, so switching days shouldn't silently reset it back to some
    /// default range out from under whatever the Dashboard's W/M picker
    /// currently has selected. Range-based (not `daysBack`) so the chart
    /// anchors to a real calendar week/month rather than a trailing window.
    /// Called on first appearance, on pull to refresh, and whenever that
    /// picker changes.
    func loadWeights(from: Date, to: Date) async {
        recentWeights = (try? await bodyWeightRepository.fetchRange(from: from, to: to)) ?? []
    }

    /// This week's steps debt/nutrition debt - independent of `load(date:)`
    /// and `selectedDate` (ported from `WeeklyInsightsViewModel`, which used
    /// to compute this for whichever week was selected there; here it's
    /// always the current Monday-Sunday week, since a debt figure only
    /// makes sense as "what do I need today"). Called on first appearance
    /// and pull-to-refresh, same as `loadOffPlanInsights()`.
    func loadCurrentWeekDebts() async {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekStart = DateFormatting.mondayOfWeek(containing: today, calendar: calendar)
        let sundayThisWeek = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart

        async let pastGoalsResult = try? goalsRepository.fetchPastGoals(limit: 100)
        async let weekStepLogsResult = try? healthRepository.fetchStepLogs(from: weekStart, to: sundayThisWeek)
        async let nutritionLogsResult = try? nutritionRepository.fetchRange(from: weekStart, to: sundayThisWeek)
        async let preferencesResult = try? preferencesRepository.fetch()
        async let cardioStepSessionsResult = try? cardioStepSessionRepository.fetchSessions(from: weekStart, to: sundayThisWeek)

        let allGoals = (await pastGoalsResult ?? []).sorted { $0.effectiveFrom < $1.effectiveFrom }
        let isoToday = DateFormatting.isoDate(today)
        let resolvedGoal = allGoals.last { $0.effectiveFrom <= isoToday }

        let exclusionEnabled = (await preferencesResult ?? nil)?.cardioStepExclusionEnabled ?? false
        let cardioStepSessions = await cardioStepSessionsResult ?? []
        let excludedStepsByDate = Dictionary(grouping: cardioStepSessions, by: \.date)
            .mapValues { $0.reduce(0) { $0 + $1.stepsDelta } }

        let weekStepLogs = await weekStepLogsResult ?? []
        let weekStepsByDate: [String: Int] = Dictionary(uniqueKeysWithValues: weekStepLogs.map { log in
            let adjusted = exclusionEnabled ? max(log.stepCount - (excludedStepsByDate[log.date] ?? 0), 0) : log.stepCount
            return (log.date, adjusted)
        })

        // Today is always inside [weekStart, sundayThisWeek] here (this is
        // always the current week), so "days elapsed" is simply the gap
        // from Monday to today - no past-week edge case to handle, unlike
        // Weekly Insights' version of this same calculation.
        let completedDays = max(0, min(7, calendar.dateComponents([.day], from: weekStart, to: today).day ?? 0))

        var actualStepsCompleted = 0
        for offset in 0..<completedDays {
            let date = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
            actualStepsCompleted += weekStepsByDate[DateFormatting.isoDate(date)] ?? 0
        }
        // Today's live count (if anything's synced yet) is folded back in
        // here even though it's not one of the "completed" days above - the
        // debt/pace numbers exist to answer "am I on track *right now*."
        let todaysStepsSoFar = weekStepsByDate[isoToday] ?? 0
        let stepsBankedTowardDebt = actualStepsCompleted + todaysStepsSoFar

        stepsDebt = {
            guard let stepTarget = resolvedGoal?.stepTarget else { return nil }
            let remainingDays = 7 - completedDays
            let stepsBehindPace = stepsBankedTowardDebt - stepTarget * completedDays
            let requiredPerDayForRest = remainingDays > 0
                ? max(0, (stepTarget * 7 - stepsBankedTowardDebt + remainingDays - 1) / remainingDays)
                : 0
            return StepsDebt(
                completedDays: completedDays,
                remainingDays: remainingDays,
                stepsBehindPace: stepsBehindPace,
                requiredPerDayForRest: requiredPerDayForRest
            )
        }()

        let nutritionLogs = await nutritionLogsResult ?? []
        let nutritionByDate = Dictionary(uniqueKeysWithValues: nutritionLogs.map { ($0.date, $0) })
        func macroDebt(target: Double?, keyPath: KeyPath<NutritionLog, Double>) -> MacroDebt? {
            guard let target, target > 0 else { return nil }
            var completedTotal = 0.0
            for offset in 0..<completedDays {
                let date = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
                if let log = nutritionByDate[DateFormatting.isoDate(date)] {
                    completedTotal += log[keyPath: keyPath]
                }
            }
            let todaysSoFar = nutritionByDate[isoToday]?[keyPath: keyPath] ?? 0
            let banked = completedTotal + todaysSoFar
            let remainingDays = 7 - completedDays
            let requiredPerDayForRest = remainingDays > 0 ? max(0, (target * 7 - banked) / Double(remainingDays)) : 0
            return MacroDebt(target: target, completedDays: completedDays, remainingDays: remainingDays, requiredPerDayForRest: requiredPerDayForRest)
        }
        nutritionDebt = NutritionDebtSummary(
            calories: macroDebt(target: resolvedGoal?.dailyCalorieTarget, keyPath: \.calories),
            protein: macroDebt(target: resolvedGoal?.proteinGTarget, keyPath: \.proteinG),
            carbs: macroDebt(target: resolvedGoal?.carbsGTarget, keyPath: \.carbsG),
            fat: macroDebt(target: resolvedGoal?.fatGTarget, keyPath: \.fatG)
        )
    }

    /// Both halves of `OffPlanWeightAdvisor`, independent of `selectedDate`
    /// and the Weight card's own chart range - advisory only, so any
    /// failure here just leaves both nil rather than surfacing an error.
    func loadOffPlanInsights() async {
        async let trendWeightsResult = try? bodyWeightRepository.fetchRecent(days: offPlanTrendWindowDays)
        async let recentCheckinsResult = try? dailyCheckinRepository.fetchRecent(days: recentFlagLookbackDays)
        let trendWeights = await trendWeightsResult ?? []
        let recentCheckins = await recentCheckinsResult ?? []
        offPlanRecentInsight = OffPlanWeightAdvisor.evaluateRecentFlag(weights: trendWeights, recentCheckins: recentCheckins)

        guard let offPlanDays = try? await dailyCheckinRepository.fetchOffPlanDays(), !offPlanDays.isEmpty else {
            offPlanHistoricalStat = nil
            return
        }
        let calendar = Calendar.current
        guard let earliestCheckinDate = offPlanDays.compactMap({ DateFormatting.date(fromISODate: $0.checkinDate) }).min(),
              let earliestOffPlanDay = calendar.date(byAdding: .day, value: -1, to: earliestCheckinDate)
        else {
            offPlanHistoricalStat = nil
            return
        }
        let weights = (try? await bodyWeightRepository.fetchRange(from: earliestOffPlanDay, to: Date())) ?? []
        let weightsByDate = Dictionary(grouping: weights) { calendar.startOfDay(for: $0.loggedAt) }
            .mapValues { logs in logs.reduce(0) { $0 + $1.weightKg } / Double(logs.count) }
        offPlanHistoricalStat = OffPlanWeightAdvisor.evaluateHistory(offPlanCheckins: offPlanDays, weightsByDate: weightsByDate)
    }
}
