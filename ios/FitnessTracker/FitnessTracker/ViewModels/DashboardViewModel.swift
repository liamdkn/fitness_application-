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
    @Published var nutritionInsight: TDEEEstimate?
    @Published var isApplyingNutritionInsight = false
    @Published var errorMessage: String?
    @Published var isLoading = false

    private let goalsRepository = GoalsRepository()
    private let nutritionRepository = NutritionRepository()
    private let healthRepository = HealthRepository()
    private let workoutRepository = WorkoutRepository()
    private let bodyWeightRepository = BodyWeightRepository()
    private let preferencesRepository = UserPreferencesRepository()
    private let cardioStepSessionRepository = CardioStepSessionRepository()
    private let tdeeEstimateRepository = TDEEEstimateRepository()
    private let tdeeWindowDays = 21

    func load(date: Date = Date()) async {
        isLoading = true
        defer { isLoading = false }

        async let goalResult = try? goalsRepository.fetchCurrentGoal()
        async let nutritionResult = try? nutritionRepository.fetchLog(date: date)
        async let stepsResult = try? healthRepository.fetchStepLog(date: date)
        async let sleepResult = try? healthRepository.fetchSleepLog(date: date)
        async let volumeResult = try? workoutRepository.fetchWeeklyVolumeKg()
        async let weightsResult = try? bodyWeightRepository.fetchRecent(days: 30)
        async let preferencesResult = try? preferencesRepository.fetch()
        async let cardioSessionsResult = try? cardioStepSessionRepository.fetchSessions(date: date)

        goal = await goalResult ?? nil
        todayNutrition = await nutritionResult ?? nil
        todaySteps = (await stepsResult ?? nil)?.stepCount
        lastNightSleepMinutes = (await sleepResult ?? nil)?.totalSleepMinutes
        weeklyVolumeKg = await volumeResult ?? nil
        recentWeights = await weightsResult ?? []
        weightTrendPoints = TrendWeightCalculator.compute(from: recentWeights)
        cardioExclusionEnabled = (await preferencesResult ?? nil)?.cardioStepExclusionEnabled ?? false
        let cardioSessions = await cardioSessionsResult ?? []
        cardioStepsExcludedToday = cardioSessions.reduce(0) { $0 + $1.stepsDelta }

        await refreshNutritionInsight()
    }

    /// Surfaces an adaptive-TDEE calorie recommendation on the Dashboard.
    /// Only recomputes roughly weekly (a fresh estimate replaces a week-old
    /// one); a still-pending recent estimate is just re-shown rather than
    /// recalculated on every load.
    private func refreshNutritionInsight() async {
        guard let goal else {
            nutritionInsight = nil
            return
        }
        do {
            if let latest = try await tdeeEstimateRepository.fetchLatest(),
               let estimatedDate = DateFormatting.date(fromISODate: latest.estimatedAt),
               (Calendar.current.dateComponents([.day], from: estimatedDate, to: Date()).day ?? 99) < 7 {
                nutritionInsight = latest.status == .pending ? latest : nil
                return
            }

            guard let windowStart = Calendar.current.date(byAdding: .day, value: -tdeeWindowDays, to: Date()) else {
                nutritionInsight = nil
                return
            }
            let windowNutrition = try await nutritionRepository.fetchRange(from: windowStart, to: Date())

            guard let recommendation = AdaptiveTDEEEngine.evaluate(
                weightLogs: recentWeights,
                nutritionLogs: windowNutrition,
                goal: goal,
                windowDays: tdeeWindowDays
            ), recommendation.isActionable else {
                nutritionInsight = nil
                return
            }

            nutritionInsight = try await tdeeEstimateRepository.save(recommendation)
        } catch {
            // Advisory only - don't block the Dashboard on this failing.
        }
    }

    func acceptNutritionInsight() async {
        guard let insight = nutritionInsight, let goal else { return }
        isApplyingNutritionInsight = true
        defer { isApplyingNutritionInsight = false }
        do {
            self.goal = try await goalsRepository.applyCalorieAdjustment(
                to: goal,
                newCalorieTarget: insight.recommendedCalorieTarget
            )
            try await tdeeEstimateRepository.updateStatus(id: insight.id, status: .accepted)
            nutritionInsight = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func dismissNutritionInsight() async {
        guard let insight = nutritionInsight else { return }
        do {
            try await tdeeEstimateRepository.updateStatus(id: insight.id, status: .dismissed)
        } catch {
            // Non-critical - the card just won't reappear until the next
            // weekly recompute either way.
        }
        nutritionInsight = nil
    }
}
