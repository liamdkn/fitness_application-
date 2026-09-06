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

    private struct UpsertStepSource: Encodable {
        let user_id: UUID
        let step_source: String
    }

    private struct UpsertEnabledCardioTypes: Encodable {
        let user_id: UUID
        let enabled_cardio_types: [String]
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
        return rows.first ?? UserPreferences(
            weeklyCheckinWeekday: 2,
            cardioStepExclusionEnabled: false,
            stepSource: .merged,
            enabledCardioTypes: [CardioType.inclineTreadmill.rawValue, CardioType.stairmaster.rawValue]
        )
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

    @discardableResult
    func setStepSource(_ source: StepSource) async throws -> UserPreferences {
        let userId = try await client.auth.session.user.id
        let saved: [UserPreferences] = try await client
            .from("user_preferences")
            .upsert(UpsertStepSource(user_id: userId, step_source: source.rawValue), onConflict: "user_id")
            .select()
            .execute()
            .value
        guard let preferences = saved.first else {
            throw RepositoryError.insertFailed
        }
        return preferences
    }

    @discardableResult
    func setEnabledCardioTypes(_ types: [CardioType]) async throws -> UserPreferences {
        let userId = try await client.auth.session.user.id
        let saved: [UserPreferences] = try await client
            .from("user_preferences")
            .upsert(UpsertEnabledCardioTypes(user_id: userId, enabled_cardio_types: types.map(\.rawValue)), onConflict: "user_id")
            .select()
            .execute()
            .value
        guard let preferences = saved.first else {
            throw RepositoryError.insertFailed
        }
        return preferences
    }
}
