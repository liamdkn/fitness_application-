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
}
