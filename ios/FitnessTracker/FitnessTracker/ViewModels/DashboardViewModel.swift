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
    @Published var todayCardioSessions: [CardioStepSession] = []
    @Published var errorMessage: String?
    @Published var isLoading = false

    private let goalsRepository = GoalsRepository()
    private let nutritionRepository = NutritionRepository()
    private let healthRepository = HealthRepository()
    private let workoutRepository = WorkoutRepository()
    private let bodyWeightRepository = BodyWeightRepository()
    private let preferencesRepository = UserPreferencesRepository()
    private let cardioStepSessionRepository = CardioStepSessionRepository()

    func load() async {
        isLoading = true
        defer { isLoading = false }

        async let goalResult = try? goalsRepository.fetchCurrentGoal()
        async let nutritionResult = try? nutritionRepository.fetchLog(date: Date())
        async let stepsResult = try? healthRepository.fetchStepLog(date: Date())
        async let sleepResult = try? healthRepository.fetchSleepLog(date: Date())
        async let volumeResult = try? workoutRepository.fetchWeeklyVolumeKg()
        async let weightsResult = try? bodyWeightRepository.fetchRecent(days: 30)
        async let preferencesResult = try? preferencesRepository.fetch()
        async let cardioSessionsResult = try? cardioStepSessionRepository.fetchSessions(date: Date())

        goal = await goalResult ?? nil
        todayNutrition = await nutritionResult ?? nil
        todaySteps = (await stepsResult ?? nil)?.stepCount
        lastNightSleepMinutes = (await sleepResult ?? nil)?.totalSleepMinutes
        weeklyVolumeKg = await volumeResult ?? nil
        recentWeights = await weightsResult ?? []
        cardioExclusionEnabled = (await preferencesResult ?? nil)?.cardioStepExclusionEnabled ?? false
        todayCardioSessions = await cardioSessionsResult ?? []
        cardioStepsExcludedToday = todayCardioSessions.reduce(0) { $0 + $1.stepsDelta }
    }

    func logCardioStepSession(before: Int, after: Int) async {
        do {
            _ = try await cardioStepSessionRepository.logSession(date: Date(), stepsBefore: before, stepsAfter: after)
            todayCardioSessions = try await cardioStepSessionRepository.fetchSessions(date: Date())
            cardioStepsExcludedToday = todayCardioSessions.reduce(0) { $0 + $1.stepsDelta }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteCardioStepSession(id: UUID) async {
        do {
            try await cardioStepSessionRepository.deleteSession(id: id)
            todayCardioSessions.removeAll { $0.id == id }
            cardioStepsExcludedToday = todayCardioSessions.reduce(0) { $0 + $1.stepsDelta }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logWeight(kg: Double) async {
        do {
            _ = try await bodyWeightRepository.logWeight(kg: kg)
            recentWeights = try await bodyWeightRepository.fetchRecent(days: 30)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
