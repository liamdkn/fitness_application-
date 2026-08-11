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
    private let daysBack = 14

    private init() {}

    func requestAuthorizationAndSync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        do {
            try await healthKit.requestAuthorization()
            let userId = try await SupabaseService.shared.client.auth.session.user.id

            async let steps = healthKit.fetchDailySteps(daysBack: daysBack)
            async let sleep = healthKit.fetchDailySleep(daysBack: daysBack)

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

            try await repository.upsertSteps(stepLogs)
            try await repository.upsertSleep(sleepLogs)

            lastSyncedAt = Date()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
