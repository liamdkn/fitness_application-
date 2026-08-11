import Foundation
import Supabase

struct BodyWeightRepository {
    let client = SupabaseService.shared.client

    private struct NewBodyWeightLog: Encodable {
        let user_id: UUID
        let weight_kg: Double
        let source: String
    }

    func fetchRecent(days: Int) async throws -> [BodyWeightLog] {
        let calendar = Calendar.current
        let since = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return try await client
            .from("body_weight_logs")
            .select()
            .gte("logged_at", value: since.ISO8601Format())
            .order("logged_at")
            .execute()
            .value
    }

    @discardableResult
    func logWeight(kg: Double) async throws -> BodyWeightLog {
        let userId = try await client.auth.session.user.id
        let inserted: [BodyWeightLog] = try await client
            .from("body_weight_logs")
            .insert(NewBodyWeightLog(user_id: userId, weight_kg: kg, source: "manual"))
            .select()
            .execute()
            .value
        guard let log = inserted.first else {
            throw RepositoryError.insertFailed
        }
        return log
    }
}
