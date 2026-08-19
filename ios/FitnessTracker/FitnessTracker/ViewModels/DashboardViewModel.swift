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
        cardioExclusionEnabled = (await preferencesResult ?? nil)?.cardioStepExclusionEnabled ?? false
        let cardioSessions = await cardioSessionsResult ?? []
        cardioStepsExcludedToday = cardioSessions.reduce(0) { $0 + $1.stepsDelta }
    }
}
