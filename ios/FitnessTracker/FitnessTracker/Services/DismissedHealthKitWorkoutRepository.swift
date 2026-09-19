import Foundation
import Supabase

/// Tracks which detected Apple Watch workouts the user explicitly said no
/// to importing/enriching - without this, the same candidate would keep
/// reappearing on every future review since nothing else marks it as
/// "seen" (a declined workout never gets a `healthkit_uuid` anywhere else).
struct DismissedHealthKitWorkoutRepository {
    let client = SupabaseService.shared.client

    private struct NewDismissal: Encodable {
        let user_id: UUID
        let healthkit_uuid: String
    }

    private struct DismissalRow: Decodable {
        let healthkitUUID: String

        enum CodingKeys: String, CodingKey {
            case healthkitUUID = "healthkit_uuid"
        }
    }

    func fetchDismissedIds() async throws -> Set<String> {
        let rows: [DismissalRow] = try await client
            .from("dismissed_healthkit_workouts")
            .select("healthkit_uuid")
            .execute()
            .value
        return Set(rows.map(\.healthkitUUID))
    }

    func dismiss(healthkitUUID: String) async throws {
        let userId = try await client.auth.session.user.id
        try await client
            .from("dismissed_healthkit_workouts")
            .upsert(NewDismissal(user_id: userId, healthkit_uuid: healthkitUUID), onConflict: "user_id,healthkit_uuid")
            .execute()
    }
}
