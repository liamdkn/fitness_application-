import Foundation
import Supabase

struct StepLogRecord: Decodable {
    let date: String
    let stepCount: Int

    enum CodingKeys: String, CodingKey {
        case date
        case stepCount = "step_count"
    }
}

struct SleepLogRecord: Decodable {
    let date: String
    let totalSleepMinutes: Int

    enum CodingKeys: String, CodingKey {
        case date
        case totalSleepMinutes = "total_sleep_minutes"
    }
}

struct HealthRepository {
    let client = SupabaseService.shared.client

    func upsertSteps(_ logs: [StepLog]) async throws {
        guard !logs.isEmpty else { return }
        try await client
            .from("step_logs")
            .upsert(logs, onConflict: "user_id,date")
            .execute()
    }

    func upsertSleep(_ logs: [SleepLog]) async throws {
        guard !logs.isEmpty else { return }
        try await client
            .from("sleep_logs")
            .upsert(logs, onConflict: "user_id,date")
            .execute()
    }

    func fetchStepLog(date: Date) async throws -> StepLogRecord? {
        let logs: [StepLogRecord] = try await client
            .from("step_logs")
            .select("date,step_count")
            .eq("date", value: DateFormatting.isoDate(date))
            .limit(1)
            .execute()
            .value
        return logs.first
    }

    func fetchSleepLog(date: Date) async throws -> SleepLogRecord? {
        let logs: [SleepLogRecord] = try await client
            .from("sleep_logs")
            .select("date,total_sleep_minutes")
            .eq("date", value: DateFormatting.isoDate(date))
            .limit(1)
            .execute()
            .value
        return logs.first
    }
}
