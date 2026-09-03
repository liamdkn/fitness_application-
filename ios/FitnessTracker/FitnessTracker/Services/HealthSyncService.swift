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

    /// A sync that starts the instant this app comes back to the
    /// foreground (see `MainTabView`'s `scenePhase` handler) can race
    /// whatever just wrote to Health a moment earlier - e.g. switching
    /// straight back from MyFitnessPal after logging a meal, where
    /// HealthKit's own store occasionally hasn't finished indexing that
    /// write yet when our query runs. That shows up as "MFP sometimes
    /// doesn't sync" even though the data is there seconds later - a plain
    /// one-shot sync has no way to recover from that until the next
    /// foreground/launch. One short-delay retry on failure covers it
    /// without masking a real, persistent problem (which will still fail
    /// on the second attempt and surface `errorMessage` as before).
    private let retryDelayNanoseconds: UInt64 = 2_000_000_000

    func requestAuthorizationAndSync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        for attempt in 1...2 {
            do {
                try await performSync()
                lastSyncedAt = Date()
                errorMessage = nil
                return
            } catch {
                if attempt == 2 {
                    errorMessage = error.localizedDescription
                } else {
                    try? await Task.sleep(nanoseconds: retryDelayNanoseconds)
                }
            }
        }
    }

    private func performSync() async throws {
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
    }
}
