import Foundation
import Supabase

struct NutritionRepository {
    let client = SupabaseService.shared.client

    private struct UpsertNutritionLog: Encodable {
        let user_id: UUID
        let date: String
        let calories: Double
        let protein_g: Double
        let carbs_g: Double
        let fat_g: Double
        let source: String
    }

    struct SyncedNutritionLog {
        let date: String
        let calories: Double
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
    }

    func fetchLog(date: Date) async throws -> NutritionLog? {
        let dateString = DateFormatting.isoDate(date)
        let logs: [NutritionLog] = try await client
            .from("nutrition_logs")
            .select()
            .eq("date", value: dateString)
            .limit(1)
            .execute()
            .value
        return logs.first
    }

    func fetchRecent(days: Int) async throws -> [NutritionLog] {
        try await client
            .from("nutrition_logs")
            .select()
            .order("date", ascending: false)
            .limit(days)
            .execute()
            .value
    }

    /// All logged days within an inclusive calendar range (as opposed to
    /// `fetchRecent`'s row-count limit), used where the caller needs the
    /// window to line up with a date range from another source - e.g.
    /// matching the adaptive TDEE engine's weight-log window.
    func fetchRange(from: Date, to: Date) async throws -> [NutritionLog] {
        try await client
            .from("nutrition_logs")
            .select()
            .gte("date", value: DateFormatting.isoDate(from))
            .lte("date", value: DateFormatting.isoDate(to))
            .order("date")
            .execute()
            .value
    }

    @discardableResult
    func upsertLog(date: Date, calories: Double, proteinG: Double, carbsG: Double, fatG: Double) async throws -> NutritionLog {
        let userId = try await client.auth.session.user.id
        let payload = UpsertNutritionLog(
            user_id: userId,
            date: DateFormatting.isoDate(date),
            calories: calories,
            protein_g: proteinG,
            carbs_g: carbsG,
            fat_g: fatG,
            source: "manual"
        )
        let logs: [NutritionLog] = try await client
            .from("nutrition_logs")
            .upsert(payload, onConflict: "user_id,date")
            .select()
            .execute()
            .value
        guard let log = logs.first else {
            throw RepositoryError.insertFailed
        }
        return log
    }

    private struct DateOnlyRow: Decodable {
        let date: String
    }

    /// Batch upsert for the HealthKit sync path (mirrors
    /// `HealthRepository.upsertSteps`/`upsertSleep`). This user has no real
    /// HealthKit nutrition source - every "healthkit" row here is really a
    /// blank/zero reading, and a day already logged manually (typically
    /// pasted-in MFP totals via `upsertLog`, tagged `source: "manual"`)
    /// should stick rather than get silently blown away the next time this
    /// sync runs. So any date in this batch that's already manually logged
    /// is dropped from the payload before the upsert, leaving that row
    /// untouched; only genuinely un-logged days get the HealthKit value.
    func upsertLogs(_ logs: [SyncedNutritionLog]) async throws {
        guard !logs.isEmpty else { return }
        let userId = try await client.auth.session.user.id

        let candidateDates = logs.map(\.date)
        let manuallyLoggedDates: Set<String> = try await {
            let rows: [DateOnlyRow] = try await client
                .from("nutrition_logs")
                .select("date")
                .eq("source", value: "manual")
                .in("date", values: candidateDates)
                .execute()
                .value
            return Set(rows.map(\.date))
        }()

        let payload = logs
            .filter { !manuallyLoggedDates.contains($0.date) }
            .map {
                UpsertNutritionLog(
                    user_id: userId,
                    date: $0.date,
                    calories: $0.calories,
                    protein_g: $0.proteinG,
                    carbs_g: $0.carbsG,
                    fat_g: $0.fatG,
                    source: "healthkit"
                )
            }
        guard !payload.isEmpty else { return }
        try await client
            .from("nutrition_logs")
            .upsert(payload, onConflict: "user_id,date")
            .execute()
    }
}
