import Combine
import Foundation
import Supabase

@MainActor
final class HealthSyncService: ObservableObject {
    static let shared = HealthSyncService()

    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isSyncing = false

    private let healthKit = HealthKitManager()
    private let repository = HealthRepository()
    private let nutritionRepository = NutritionRepository()
    private let preferencesRepository = UserPreferencesRepository()
    private let daysBack = 14

    private init() {}

    func requestAuthorizationAndSync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            try await healthKit.requestAuthorization()
            let userId = try await SupabaseService.shared.client.auth.session.user.id
            let stepSource = try await preferencesRepository.fetch().stepSource

            async let steps = healthKit.fetchDailySteps(daysBack: daysBack, source: stepSource)
            async let sleep = healthKit.fetchDailySleep(daysBack: daysBack)
            async let nutrition = healthKit.fetchDailyNutrition(daysBack: daysBack)

            let stepLogs = try await steps.map { date, count in
                StepLog(userId: userId, date: DateFormatting.isoDate(date), stepCount: count, source: "healthkit")
            }
            let sleepLogs = try await sleep.map { date, value in
                SleepLog(
                    userId: userId,
                    date: DateFormatting.isoDate(date),
                    totalSleepMinutes: value.totalMinutes,
                    inBedMinutes: value.inBedMinutes,
                    source: "healthkit"
                )
            }
            let nutritionLogs = try await nutrition.map { date, value in
                NutritionRepository.SyncedNutritionLog(
                    date: DateFormatting.isoDate(date),
                    calories: value.calories,
                    proteinG: value.proteinG,
                    carbsG: value.carbsG,
                    fatG: value.fatG
                )
            }

            try await repository.upsertSteps(stepLogs)
            try await repository.upsertSleep(sleepLogs)
            try await nutritionRepository.upsertLogs(nutritionLogs)

            lastSyncedAt = Date()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
