import Foundation
import Supabase

struct UserPreferencesRepository {
    let client = SupabaseService.shared.client

    private struct UpsertPreferences: Encodable {
        let user_id: UUID
        let weekly_checkin_weekday: Int
    }

    private struct UpsertLiquidsSettings: Encodable {
        let user_id: UUID
        let sodium_limit_mg: Int
        let caffeine_limit_mg: Int
        let bedtime_minutes: Int
        let caffeine_half_life_hours: Double
        let caffeine_bedtime_target_mg: Int
        let bedtime_from_health: Bool
        let caffeine_reminders_enabled: Bool
    }

    /// `milk_food_id` / `milk_applied_date` go as explicit nulls so clearing works.
    private struct UpsertMilkAllowance: Encodable {
        let user_id: UUID
        let milk_allowance_enabled: Bool
        let milk_allowance_ml: Int
        let milk_food_id: UUID?

        enum CodingKeys: String, CodingKey { case user_id, milk_allowance_enabled, milk_allowance_ml, milk_food_id }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(user_id, forKey: .user_id)
            try c.encode(milk_allowance_enabled, forKey: .milk_allowance_enabled)
            try c.encode(milk_allowance_ml, forKey: .milk_allowance_ml)
            try c.encode(milk_food_id, forKey: .milk_food_id)
        }
    }

    private struct UpsertMilkApplied: Encodable {
        let user_id: UUID
        let milk_applied_date: String
    }

    private struct UpsertStepReminders: Encodable {
        let user_id: UUID
        let step_reminders_enabled: Bool
        let step_reminder_minutes: Int
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

    private struct UpsertDailyWaterMlTargetRange: Encodable {
        let user_id: UUID
        let daily_water_ml_target_min: Int
        let daily_water_ml_target_max: Int
    }

    // Manually implements `encode(to:)` because the auto-synthesized conformance
    // uses `encodeIfPresent` for Optional properties, which OMITS the JSON key
    // entirely when a value is nil - clearing the preferred gym back to "none"
    // (preferred_gym_id: nil) needs that key sent as an explicit null, or the
    // column just keeps its old value. Same fix used elsewhere in this codebase
    // (`DailyCheckinRepository`, `CardioSessionRepository`, `WeeklyScheduleRepository`)
    // for the same reason.
    private struct UpsertPreferredGym: Encodable {
        let user_id: UUID
        let preferred_gym_id: UUID?

        enum CodingKeys: String, CodingKey { case user_id, preferred_gym_id }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(user_id, forKey: .user_id)
            try container.encode(preferred_gym_id, forKey: .preferred_gym_id)
        }
    }

    /// Read with a last-known-good fallback, so the reminders, widgets and
    /// milk allowance still have their settings with no connection.
    func fetch() async throws -> UserPreferences {
        try await cachedRead(key: "user-preferences") { try await fetchFromServer() }
    }

    func setMilkAllowance(enabled: Bool, ml: Int, foodId: UUID?) async throws {
        let userId = try await client.auth.session.user.id
        try await client
            .from("user_preferences")
            .upsert(UpsertMilkAllowance(user_id: userId, milk_allowance_enabled: enabled, milk_allowance_ml: ml, milk_food_id: foodId), onConflict: "user_id")
            .execute()
    }

    func markMilkApplied(date: String) async throws {
        let userId = try await client.auth.session.user.id
        try await client
            .from("user_preferences")
            .upsert(UpsertMilkApplied(user_id: userId, milk_applied_date: date), onConflict: "user_id")
            .execute()
    }

    private func fetchFromServer() async throws -> UserPreferences {
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
            enabledCardioTypes: [CardioType.inclineTreadmill.rawValue, CardioType.stairmaster.rawValue],
            preferredGymId: nil,
            dailyWaterMlTargetMin: 2500,
            dailyWaterMlTargetMax: 3000
        )
    }

    @discardableResult
    func setDailyWaterMlTargetRange(min: Int, max: Int) async throws -> UserPreferences {
        let userId = try await client.auth.session.user.id
        let saved: [UserPreferences] = try await client
            .from("user_preferences")
            .upsert(
                UpsertDailyWaterMlTargetRange(user_id: userId, daily_water_ml_target_min: min, daily_water_ml_target_max: max),
                onConflict: "user_id"
            )
            .select()
            .execute()
            .value
        guard let preferences = saved.first else {
            throw RepositoryError.insertFailed
        }
        return preferences
    }

    @discardableResult
    func setLiquidsSettings(
        sodiumLimitMg: Int, caffeineLimitMg: Int, bedtimeMinutes: Int, halfLifeHours: Double, bedtimeTargetMg: Int,
        bedtimeFromHealth: Bool, remindersEnabled: Bool
    ) async throws -> UserPreferences {
        let userId = try await client.auth.session.user.id
        let saved: [UserPreferences] = try await client
            .from("user_preferences")
            .upsert(
                UpsertLiquidsSettings(
                    user_id: userId,
                    sodium_limit_mg: sodiumLimitMg,
                    caffeine_limit_mg: caffeineLimitMg,
                    bedtime_minutes: bedtimeMinutes,
                    caffeine_half_life_hours: halfLifeHours,
                    caffeine_bedtime_target_mg: bedtimeTargetMg,
                    bedtime_from_health: bedtimeFromHealth,
                    caffeine_reminders_enabled: remindersEnabled
                ),
                onConflict: "user_id"
            )
            .select()
            .execute()
            .value
        guard let preferences = saved.first else {
            throw RepositoryError.insertFailed
        }
        return preferences
    }

    @discardableResult
    func setPreferredGym(_ gymId: UUID?) async throws -> UserPreferences {
        let userId = try await client.auth.session.user.id
        let saved: [UserPreferences] = try await client
            .from("user_preferences")
            .upsert(UpsertPreferredGym(user_id: userId, preferred_gym_id: gymId), onConflict: "user_id")
            .select()
            .execute()
            .value
        guard let preferences = saved.first else {
            throw RepositoryError.insertFailed
        }
        return preferences
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
    func setStepReminders(enabled: Bool, minutes: Int) async throws -> UserPreferences {
        let userId = try await client.auth.session.user.id
        let saved: [UserPreferences] = try await client
            .from("user_preferences")
            .upsert(
                UpsertStepReminders(user_id: userId, step_reminders_enabled: enabled, step_reminder_minutes: minutes),
                onConflict: "user_id"
            )
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
