import Foundation
import Supabase

struct CardioStepSessionRepository {
    let client = SupabaseService.shared.client

    private struct NewCardioStepSession: Encodable {
        let user_id: UUID
        let date: String
        let steps_before: Int
        let steps_after: Int
    }

    func fetchSessions(date: Date) async throws -> [CardioStepSession] {
        try await client
            .from("cardio_step_sessions")
            .select()
            .eq("date", value: DateFormatting.isoDate(date))
            .order("created_at")
            .execute()
            .value
    }

    @discardableResult
    func logSession(date: Date, stepsBefore: Int, stepsAfter: Int) async throws -> CardioStepSession {
        let userId = try await client.auth.session.user.id
        let inserted: [CardioStepSession] = try await client
            .from("cardio_step_sessions")
            .insert(NewCardioStepSession(
                user_id: userId,
                date: DateFormatting.isoDate(date),
                steps_before: stepsBefore,
                steps_after: stepsAfter
            ))
            .select()
            .execute()
            .value
        guard let session = inserted.first else {
            throw RepositoryError.insertFailed
        }
        return session
    }

    func deleteSession(id: UUID) async throws {
        try await client
            .from("cardio_step_sessions")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}
