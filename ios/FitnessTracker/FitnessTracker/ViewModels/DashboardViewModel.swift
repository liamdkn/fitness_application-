import Combine
import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var goal: UserGoal?
    @Published var todayNutrition: NutritionLog?
    @Published var todaySteps: Int?
    @Published var lastNightSleepMinutes: Int?
    @Published var weeklyVolumeKg: Double?
    @Published var recentWeights: [BodyWeightLog] = []
    /// Noise-filtered EWMA trend line for `recentWeights`, plotted
    /// alongside the raw scale readings on the Dashboard's weight chart -
    /// see `TrendWeightCalculator`.
    @Published var weightTrendPoints: [TrendWeightPoint] = []
    @Published var cardioExclusionEnabled = false
    @Published var cardioStepsExcludedToday = 0
    @Published var errorMessage: String?
    @Published var isLoading = false

    private let goalsRepository = GoalsRepository()
    private let nutritionRepository = NutritionRepository()
    private let healthRepository = HealthRepository()
    private let workoutRepository = WorkoutRepository()
    private let bodyWeightRepository = BodyWeightRepository()
    private let preferencesRepository = UserPreferencesRepository()
    private let cardioStepSessionRepository = CardioStepSessionRepository()

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
    /// default range out from under whatever the Dashboard's W/2W/M/6M
    /// picker currently has selected. Called on first appearance, on pull
    /// to refresh, and whenever that picker changes.
    func loadWeights(daysBack: Int) async {
        recentWeights = (try? await bodyWeightRepository.fetchRecent(days: daysBack)) ?? []
        weightTrendPoints = TrendWeightCalculator.compute(from: recentWeights)
    }
}
