import Foundation
import Supabase

struct GoalsRepository {
    let client = SupabaseService.shared.client

    // `current_user_goal` returns a single `user_goals` row, not a set. When
    // there's no row yet, Postgres/PostgREST represents that as a composite
    // of all-null fields (not JSON `null`), so this decodes leniently and
    // maps an all-null result to nil rather than throwing.
    private struct UserGoalRPCResult: Decodable {
        let id: UUID?
        let effectiveFrom: String?
        let phaseType: GoalPhaseType?
        let startingWeightKg: Double?
        let durationWeeks: Int?
        let dailyCalorieTarget: Double?
        let proteinGTarget: Double?
        let carbsGTarget: Double?
        let fatGTarget: Double?
        let targetWeightKg: Double?
        let weeklyWeightChangeKg: Double?
        let stepTarget: Int?
        let sleepTargetMinutes: Int?
        let cardioSessionsPerWeek: Int?
        let cardioMinutesPerSession: Int?
        let strengthSessionsPerWeek: Int?
        let strengthOptionalSessions: Int?

        enum CodingKeys: String, CodingKey {
            case id
            case effectiveFrom = "effective_from"
            case phaseType = "phase_type"
            case startingWeightKg = "starting_weight_kg"
            case durationWeeks = "duration_weeks"
            case dailyCalorieTarget = "daily_calorie_target"
            case proteinGTarget = "protein_g_target"
            case carbsGTarget = "carbs_g_target"
            case fatGTarget = "fat_g_target"
            case targetWeightKg = "target_weight_kg"
            case weeklyWeightChangeKg = "weekly_weight_change_kg"
            case stepTarget = "step_target"
            case sleepTargetMinutes = "sleep_target_minutes"
            case cardioSessionsPerWeek = "cardio_sessions_per_week"
            case cardioMinutesPerSession = "cardio_minutes_per_session"
            case strengthSessionsPerWeek = "strength_sessions_per_week"
            case strengthOptionalSessions = "strength_optional_sessions"
        }

        var goal: UserGoal? {
            guard
                let id, let effectiveFrom, let phaseType, let durationWeeks,
                let dailyCalorieTarget, let proteinGTarget
            else { return nil }
            return UserGoal(
                id: id,
                effectiveFrom: effectiveFrom,
                phaseType: phaseType,
                startingWeightKg: startingWeightKg,
                durationWeeks: durationWeeks,
                dailyCalorieTarget: dailyCalorieTarget,
                proteinGTarget: proteinGTarget,
                carbsGTarget: carbsGTarget,
                fatGTarget: fatGTarget,
                targetWeightKg: targetWeightKg,
                weeklyWeightChangeKg: weeklyWeightChangeKg,
                stepTarget: stepTarget,
                sleepTargetMinutes: sleepTargetMinutes,
                cardioSessionsPerWeek: cardioSessionsPerWeek,
                cardioMinutesPerSession: cardioMinutesPerSession,
                strengthSessionsPerWeek: strengthSessionsPerWeek,
                strengthOptionalSessions: strengthOptionalSessions
            )
        }
    }

    private struct UpsertGoal: Encodable {
        let user_id: UUID
        let effective_from: String
        let phase_type: GoalPhaseType
        let starting_weight_kg: Double?
        let duration_weeks: Int
        let daily_calorie_target: Double
        let protein_g_target: Double
        let carbs_g_target: Double?
        let fat_g_target: Double?
        let target_weight_kg: Double?
        let weekly_weight_change_kg: Double?
        let step_target: Int?
        let sleep_target_minutes: Int?
        let cardio_sessions_per_week: Int?
        let cardio_minutes_per_session: Int?
        let strength_sessions_per_week: Int?
        let strength_optional_sessions: Int?
    }

    private struct UpdateGoal: Encodable {
        let effective_from: String
        let phase_type: GoalPhaseType
        let starting_weight_kg: Double?
        let duration_weeks: Int
        let daily_calorie_target: Double
        let protein_g_target: Double
        let carbs_g_target: Double?
        let fat_g_target: Double?
        let target_weight_kg: Double?
        let weekly_weight_change_kg: Double?
        let step_target: Int?
        let sleep_target_minutes: Int?
        let cardio_sessions_per_week: Int?
        let cardio_minutes_per_session: Int?
        let strength_sessions_per_week: Int?
        let strength_optional_sessions: Int?
    }

    private struct FetchedUserGoal: Decodable {
        let id: UUID
        let effectiveFrom: String
        let phaseType: GoalPhaseType
        let startingWeightKg: Double?
        let durationWeeks: Int
        let dailyCalorieTarget: Double
        let proteinGTarget: Double
        let carbsGTarget: Double?
        let fatGTarget: Double?
        let targetWeightKg: Double?
        let weeklyWeightChangeKg: Double?
        let stepTarget: Int?
        let sleepTargetMinutes: Int?
        let cardioSessionsPerWeek: Int?
        let cardioMinutesPerSession: Int?
        let strengthSessionsPerWeek: Int?
        let strengthOptionalSessions: Int?

        enum CodingKeys: String, CodingKey {
            case id
            case effectiveFrom = "effective_from"
            case phaseType = "phase_type"
            case startingWeightKg = "starting_weight_kg"
            case durationWeeks = "duration_weeks"
            case dailyCalorieTarget = "daily_calorie_target"
            case proteinGTarget = "protein_g_target"
            case carbsGTarget = "carbs_g_target"
            case fatGTarget = "fat_g_target"
            case targetWeightKg = "target_weight_kg"
            case weeklyWeightChangeKg = "weekly_weight_change_kg"
            case stepTarget = "step_target"
            case sleepTargetMinutes = "sleep_target_minutes"
            case cardioSessionsPerWeek = "cardio_sessions_per_week"
            case cardioMinutesPerSession = "cardio_minutes_per_session"
            case strengthSessionsPerWeek = "strength_sessions_per_week"
            case strengthOptionalSessions = "strength_optional_sessions"
        }

        var goal: UserGoal {
            UserGoal(
                id: id,
                effectiveFrom: effectiveFrom,
                phaseType: phaseType,
                startingWeightKg: startingWeightKg,
                durationWeeks: durationWeeks,
                dailyCalorieTarget: dailyCalorieTarget,
                proteinGTarget: proteinGTarget,
                carbsGTarget: carbsGTarget,
                fatGTarget: fatGTarget,
                targetWeightKg: targetWeightKg,
                weeklyWeightChangeKg: weeklyWeightChangeKg,
                stepTarget: stepTarget,
                sleepTargetMinutes: sleepTargetMinutes,
                cardioSessionsPerWeek: cardioSessionsPerWeek,
                cardioMinutesPerSession: cardioMinutesPerSession,
                strengthSessionsPerWeek: strengthSessionsPerWeek,
                strengthOptionalSessions: strengthOptionalSessions
            )
        }
    }

    /// Applies an adaptive-TDEE calorie recommendation to the current goal:
    /// writes a new phase row effective today with every field carried over
    /// unchanged except the calorie target - the same "start a phase" shape
    /// `StartNewPhaseView` writes, so the change shows up in phase history
    /// rather than silently mutating an existing row.
    @discardableResult
    func applyCalorieAdjustment(to goal: UserGoal, newCalorieTarget: Double) async throws -> UserGoal {
        try await saveGoal(
            effectiveFrom: Date(),
            phaseType: goal.phaseType,
            startingWeightKg: goal.startingWeightKg,
            durationWeeks: goal.durationWeeks,
            dailyCalorieTarget: newCalorieTarget,
            proteinGTarget: goal.proteinGTarget,
            carbsGTarget: goal.carbsGTarget,
            fatGTarget: goal.fatGTarget,
            targetWeightKg: goal.targetWeightKg,
            weeklyWeightChangeKg: goal.weeklyWeightChangeKg,
            stepTarget: goal.stepTarget,
            sleepTargetMinutes: goal.sleepTargetMinutes,
            cardioSessionsPerWeek: goal.cardioSessionsPerWeek,
            cardioMinutesPerSession: goal.cardioMinutesPerSession,
            strengthSessionsPerWeek: goal.strengthSessionsPerWeek,
            strengthOptionalSessions: goal.strengthOptionalSessions
        )
    }

    func fetchCurrentGoal() async throws -> UserGoal? {
        let result: UserGoalRPCResult = try await client
            .rpc("current_user_goal")
            .execute()
            .value
        return result.goal
    }

    func fetchPastGoals(limit: Int = 20) async throws -> [UserGoal] {
        let goals: [FetchedUserGoal] = try await client
            .from("user_goals")
            .select()
            .order("effective_from", ascending: false)
            .limit(limit)
            .execute()
            .value
        return goals.map(\.goal)
    }

    @discardableResult
    func saveGoal(
        effectiveFrom: Date,
        phaseType: GoalPhaseType,
        startingWeightKg: Double?,
        durationWeeks: Int,
        dailyCalorieTarget: Double,
        proteinGTarget: Double,
        carbsGTarget: Double?,
        fatGTarget: Double?,
        targetWeightKg: Double?,
        weeklyWeightChangeKg: Double?,
        stepTarget: Int?,
        sleepTargetMinutes: Int?,
        cardioSessionsPerWeek: Int?,
        cardioMinutesPerSession: Int?,
        strengthSessionsPerWeek: Int?,
        strengthOptionalSessions: Int?
    ) async throws -> UserGoal {
        let userId = try await client.auth.session.user.id
        let payload = UpsertGoal(
            user_id: userId,
            effective_from: DateFormatting.isoDate(effectiveFrom),
            phase_type: phaseType,
            starting_weight_kg: startingWeightKg,
            duration_weeks: durationWeeks,
            daily_calorie_target: dailyCalorieTarget,
            protein_g_target: proteinGTarget,
            carbs_g_target: carbsGTarget,
            fat_g_target: fatGTarget,
            target_weight_kg: targetWeightKg,
            weekly_weight_change_kg: weeklyWeightChangeKg,
            step_target: stepTarget,
            sleep_target_minutes: sleepTargetMinutes,
            cardio_sessions_per_week: cardioSessionsPerWeek,
            cardio_minutes_per_session: cardioMinutesPerSession,
            strength_sessions_per_week: strengthSessionsPerWeek,
            strength_optional_sessions: strengthOptionalSessions
        )
        let saved: [FetchedUserGoal] = try await client
            .from("user_goals")
            .upsert(payload, onConflict: "user_id,effective_from")
            .select()
            .execute()
            .value
        guard let goal = saved.first else {
            throw RepositoryError.insertFailed
        }
        return goal.goal
    }

    @discardableResult
    func updateGoal(
        goalId: UUID,
        effectiveFrom: Date,
        phaseType: GoalPhaseType,
        startingWeightKg: Double?,
        durationWeeks: Int,
        dailyCalorieTarget: Double,
        proteinGTarget: Double,
        carbsGTarget: Double?,
        fatGTarget: Double?,
        targetWeightKg: Double?,
        weeklyWeightChangeKg: Double?,
        stepTarget: Int?,
        sleepTargetMinutes: Int?,
        cardioSessionsPerWeek: Int?,
        cardioMinutesPerSession: Int?,
        strengthSessionsPerWeek: Int?,
        strengthOptionalSessions: Int?
    ) async throws -> UserGoal {
        let payload = UpdateGoal(
            effective_from: DateFormatting.isoDate(effectiveFrom),
            phase_type: phaseType,
            starting_weight_kg: startingWeightKg,
            duration_weeks: durationWeeks,
            daily_calorie_target: dailyCalorieTarget,
            protein_g_target: proteinGTarget,
            carbs_g_target: carbsGTarget,
            fat_g_target: fatGTarget,
            target_weight_kg: targetWeightKg,
            weekly_weight_change_kg: weeklyWeightChangeKg,
            step_target: stepTarget,
            sleep_target_minutes: sleepTargetMinutes,
            cardio_sessions_per_week: cardioSessionsPerWeek,
            cardio_minutes_per_session: cardioMinutesPerSession,
            strength_sessions_per_week: strengthSessionsPerWeek,
            strength_optional_sessions: strengthOptionalSessions
        )
        let saved: [FetchedUserGoal] = try await client
            .from("user_goals")
            .update(payload)
            .eq("id", value: goalId)
            .select()
            .execute()
            .value
        guard let goal = saved.first else {
            throw RepositoryError.insertFailed
        }
        return goal.goal
    }
}
