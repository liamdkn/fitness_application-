import Foundation
import Supabase

struct UserPreferencesRepository {
    let client = SupabaseService.shared.client

    private struct UpsertPreferences: Encodable {
        let user_id: UUID
        let weekly_checkin_weekday: Int
    }

    private struct UpsertCardioStepExclusion: Encodable {
        let user_id: UUID
        let cardio_step_exclusion_enabled: Bool
    }

    func fetch() async throws -> UserPreferences {
        let userId = try await client.auth.session.user.id
        let rows: [UserPreferences] = try await client
            .from("user_preferences")
            .select()
            .eq("user_id", value: userId)
            .limit(1)
            .execute()
            .value
        return rows.first ?? UserPreferences(weeklyCheckinWeekday: 2, cardioStepExclusionEnabled: false)
    }

    @discardableResult
    func setWeeklyCheckinWeekday(_ weekday: Int) async throws -> UserPreferences {
        let userId = try await client.auth.session.user.id
        let saved: [UserPreferences] = try await client
            .from("user_preferences")
            .upsert(UpsertPreferences(user_id: userId, weekly_checkin_weekday: weekday), onConflict: "user_id")
            .select()
            .execute()
            .value
        guard let preferences = saved.first else {
            throw RepositoryError.insertFailed
        }
        return preferences
    }

    @discardableResult
    func setCardioStepExclusionEnabled(_ enabled: Bool) async throws -> UserPreferences {
        let userId = try await client.auth.session.user.id
        let saved: [UserPreferences] = try await client
            .from("user_preferences")
            .upsert(UpsertCardioStepExclusion(user_id: userId, cardio_step_exclusion_enabled: enabled), onConflict: "user_id")
            .select()
            .execute()
            .value
        guard let preferences = saved.first else {
            throw RepositoryError.insertFailed
        }
        return preferences
    }
}
