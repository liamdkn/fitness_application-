import Foundation
import Supabase

struct TDEEEstimateRepository {
    let client = SupabaseService.shared.client

    private struct NewTDEEEstimate: Encodable {
        let user_id: UUID
        let window_days: Int
        let logged_days_in_window: Int
        let avg_daily_calories: Double
        let trend_weight_change_kg_per_week: Double
        let estimated_tdee: Double
        let current_calorie_target: Double
        let recommended_calorie_target: Double
    }

    private struct StatusUpdate: Encodable {
        let status: TDEEEstimateStatus
    }

    /// Most recent estimate regardless of status, used to decide whether a
    /// fresh one needs computing this week.
    func fetchLatest() async throws -> TDEEEstimate? {
        let estimates: [TDEEEstimate] = try await client
            .from("tdee_estimates")
            .select()
            .order("estimated_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return estimates.first
    }

    @discardableResult
    func save(_ recommendation: TDEERecommendation) async throws -> TDEEEstimate {
        let userId = try await client.auth.session.user.id
        let payload = NewTDEEEstimate(
            user_id: userId,
            window_days: recommendation.windowDays,
            logged_days_in_window: recommendation.loggedDaysInWindow,
            avg_daily_calories: recommendation.avgDailyCalories,
            trend_weight_change_kg_per_week: recommendation.trendWeightChangeKgPerWeek,
            estimated_tdee: recommendation.estimatedTDEE,
            current_calorie_target: recommendation.currentCalorieTarget,
            recommended_calorie_target: recommendation.recommendedCalorieTarget
        )
        let saved: [TDEEEstimate] = try await client
            .from("tdee_estimates")
            .upsert(payload, onConflict: "user_id,estimated_at")
            .select()
            .execute()
            .value
        guard let estimate = saved.first else {
            throw RepositoryError.insertFailed
        }
        return estimate
    }

    func updateStatus(id: UUID, status: TDEEEstimateStatus) async throws {
        try await client
            .from("tdee_estimates")
            .update(StatusUpdate(status: status))
            .eq("id", value: id)
            .execute()
    }
}
