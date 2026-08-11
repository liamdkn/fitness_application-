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
        let dailyCalorieTarget: Double?
        let proteinGTarget: Double?
        let carbsGTarget: Double?
        let fatGTarget: Double?
        let targetWeightKg: Double?
        let weeklyWeightChangeKg: Double?
        let stepTarget: Int?
        let sleepTargetMinutes: Int?

        enum CodingKeys: String, CodingKey {
            case id
            case effectiveFrom = "effective_from"
            case dailyCalorieTarget = "daily_calorie_target"
            case proteinGTarget = "protein_g_target"
            case carbsGTarget = "carbs_g_target"
            case fatGTarget = "fat_g_target"
            case targetWeightKg = "target_weight_kg"
            case weeklyWeightChangeKg = "weekly_weight_change_kg"
            case stepTarget = "step_target"
            case sleepTargetMinutes = "sleep_target_minutes"
        }

        var goal: UserGoal? {
            guard let id, let effectiveFrom, let dailyCalorieTarget, let proteinGTarget else { return nil }
            return UserGoal(
                id: id,
                effectiveFrom: effectiveFrom,
                dailyCalorieTarget: dailyCalorieTarget,
                proteinGTarget: proteinGTarget,
                carbsGTarget: carbsGTarget,
                fatGTarget: fatGTarget,
                targetWeightKg: targetWeightKg,
                weeklyWeightChangeKg: weeklyWeightChangeKg,
                stepTarget: stepTarget,
                sleepTargetMinutes: sleepTargetMinutes
            )
        }
    }

    private struct UpsertGoal: Encodable {
        let user_id: UUID
        let effective_from: String
        let daily_calorie_target: Double
        let protein_g_target: Double
        let carbs_g_target: Double?
        let fat_g_target: Double?
        let target_weight_kg: Double?
        let weekly_weight_change_kg: Double?
        let step_target: Int?
        let sleep_target_minutes: Int?
    }

    private struct FetchedUserGoal: Decodable {
        let id: UUID
        let effectiveFrom: String
        let dailyCalorieTarget: Double
        let proteinGTarget: Double
        let carbsGTarget: Double?
        let fatGTarget: Double?
        let targetWeightKg: Double?
        let weeklyWeightChangeKg: Double?
        let stepTarget: Int?
        let sleepTargetMinutes: Int?

        enum CodingKeys: String, CodingKey {
            case id
            case effectiveFrom = "effective_from"
            case dailyCalorieTarget = "daily_calorie_target"
            case proteinGTarget = "protein_g_target"
            case carbsGTarget = "carbs_g_target"
            case fatGTarget = "fat_g_target"
            case targetWeightKg = "target_weight_kg"
            case weeklyWeightChangeKg = "weekly_weight_change_kg"
            case stepTarget = "step_target"
            case sleepTargetMinutes = "sleep_target_minutes"
        }

        var goal: UserGoal {
            UserGoal(
                id: id,
                effectiveFrom: effectiveFrom,
                dailyCalorieTarget: dailyCalorieTarget,
                proteinGTarget: proteinGTarget,
                carbsGTarget: carbsGTarget,
                fatGTarget: fatGTarget,
                targetWeightKg: targetWeightKg,
                weeklyWeightChangeKg: weeklyWeightChangeKg,
                stepTarget: stepTarget,
                sleepTargetMinutes: sleepTargetMinutes
            )
        }
    }

    func fetchCurrentGoal() async throws -> UserGoal? {
        let result: UserGoalRPCResult = try await client
            .rpc("current_user_goal")
            .execute()
            .value
        return result.goal
    }

    @discardableResult
    func saveGoal(
        dailyCalorieTarget: Double,
        proteinGTarget: Double,
        carbsGTarget: Double?,
        fatGTarget: Double?,
        targetWeightKg: Double?,
        weeklyWeightChangeKg: Double?,
        stepTarget: Int?,
        sleepTargetMinutes: Int?
    ) async throws -> UserGoal {
        let userId = try await client.auth.session.user.id
        let payload = UpsertGoal(
            user_id: userId,
            effective_from: DateFormatting.isoDate(Date()),
            daily_calorie_target: dailyCalorieTarget,
            protein_g_target: proteinGTarget,
            carbs_g_target: carbsGTarget,
            fat_g_target: fatGTarget,
            target_weight_kg: targetWeightKg,
            weekly_weight_change_kg: weeklyWeightChangeKg,
            step_target: stepTarget,
            sleep_target_minutes: sleepTargetMinutes
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
}
