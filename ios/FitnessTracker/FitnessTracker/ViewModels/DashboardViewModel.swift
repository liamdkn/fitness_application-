import Combine
import Foundation

/// Direction of this week's 7-day rolling average weight vs last week's -
/// see `loadWeightGlance()`.
enum WeightTrend {
    case up, down, stable
}

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var goal: UserGoal?
    @Published var todayNutrition: NutritionLog?
    @Published var todaySteps: Int?
    @Published var lastNightSleepMinutes: Int?
    @Published var weeklyVolumeKg: Double?
    /// The Weight card's glance data - today's latest reading and how it's
    /// trending, not a chart's worth of history (see `loadWeightGlance()`).
    @Published var currentWeightKg: Double?
    @Published var weightTrend: WeightTrend?
    /// How many of the 14 trailing weigh-ins `loadWeightGlance()` fetched
    /// were dropped as a post-off-plan water-weight bump before computing
    /// `weightTrend` - see `OffPlanWeightAdvisor.excludingBumpDates`. The
    /// Weight card shows a caption when this is nonzero so the trend badge
    /// doesn't read as a flat scale reading when it isn't one.
    @Published var weightGlanceExcludedBumpDays = 0
    @Published var cardioExclusionEnabled = false
    @Published var cardioStepsExcludedToday = 0
    @Published var offPlanRecentInsight: OffPlanWeightAdvisor.RecentFlagInsight?
    @Published var offPlanHistoricalStat: OffPlanWeightAdvisor.HistoricalStat?
    /// The Water card's glance data - see `loadWaterGlance()`.
    /// Everything drunk today - plain water plus every other drink.
    @Published var todayWaterMl = 0
    @Published var todayCaffeineMg = 0
    @Published var caffeineLimitMg = 400
    @Published var waterTargetMinMl = 2500
    @Published var waterTargetMaxMl = 3000
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
    private let waterRepository = WaterRepository()
    private let liquidsRepository = LiquidsRepository()
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
        async let nutritionResult = try? nutritionRepository.fetchDailyTotal(date: date)
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

    /// The Weight card's glance data, kept independent of `load()` and
    /// `selectedDate` - always "today's weight," never a past day's.
    /// Fetches 14 trailing days in one call so both rolling windows below
    /// are covered without a second query. Called on first appearance and
    /// pull-to-refresh.
    func loadWeightGlance() async {
        async let logsResult = try? bodyWeightRepository.fetchRecent(days: 14)
        async let checkinsResult = try? dailyCheckinRepository.fetchRecent(days: 14)
        let logs = await logsResult ?? []
        let checkins = await checkinsResult ?? []
        // Oldest-first (see `fetchRecent`), so the last entry is the most
        // recent weigh-in regardless of which day it landed on.
        currentWeightKg = logs.last?.weightKg

        // Trend-facing figures only - a bump-window reading still shows as
        // the raw `currentWeightKg` above and on any history/chart view,
        // it's just excluded from the averages that decide up/down/stable.
        let (cleanedLogs, excludedCount) = OffPlanWeightAdvisor.excludingBumpDates(from: logs, checkins: checkins)
        weightGlanceExcludedBumpDays = excludedCount

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let thisWeekStart = calendar.date(byAdding: .day, value: -6, to: today),
              let lastWeekStart = calendar.date(byAdding: .day, value: -13, to: today)
        else {
            weightTrend = nil
            return
        }
        let thisWeekAvg = average(cleanedLogs.filter { $0.loggedAt >= thisWeekStart }.map(\.weightKg))
        let lastWeekAvg = average(cleanedLogs.filter { $0.loggedAt >= lastWeekStart && $0.loggedAt < thisWeekStart }.map(\.weightKg))
        guard let thisWeekAvg, let lastWeekAvg else {
            weightTrend = nil
            return
        }
        let delta = thisWeekAvg - lastWeekAvg
        weightTrend = abs(delta) < 0.2 ? .stable : (delta > 0 ? .up : .down)
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

    /// The Water card's glance data - always "today," independent of
    /// `selectedDate` the same way `loadWeightGlance()` is (you're always
    /// logging water for right now, not a past day).
    func loadWaterGlance() async {
        async let dayResult = try? liquidsRepository.fetchDay(date: Date())
        async let preferencesResult = try? preferencesRepository.fetch()
        let day = await dayResult
        todayWaterMl = Int((day?.hydrationMl ?? 0).rounded())
        todayCaffeineMg = Int((day?.caffeineMg ?? 0).rounded())
        let preferences = await preferencesResult ?? nil
        caffeineLimitMg = preferences?.caffeineLimitMg ?? 400
        waterTargetMinMl = preferences?.dailyWaterMlTargetMin ?? 2500
        waterTargetMaxMl = preferences?.dailyWaterMlTargetMax ?? 3000
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
