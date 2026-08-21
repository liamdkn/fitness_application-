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

    /// All sessions within an inclusive calendar range - mirrors
    /// `NutritionRepository.fetchRange`, used to apply the cardio-step
    /// exclusion preference across a multi-day window (e.g. weekly
    /// aggregation) instead of one day at a time.
    func fetchSessions(from: Date, to: Date) async throws -> [CardioStepSession] {
        try await client
            .from("cardio_step_sessions")
            .select()
            .gte("date", value: DateFormatting.isoDate(from))
            .lte("date", value: DateFormatting.isoDate(to))
            .order("date")
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
}
