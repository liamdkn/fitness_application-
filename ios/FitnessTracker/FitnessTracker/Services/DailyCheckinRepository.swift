import Foundation
import Supabase

struct DailyCheckinRepository {
    let client = SupabaseService.shared.client

    private struct NewDailyCheckin: Encodable {
        let user_id: UUID
        let checkin_date: String
        let weight_kg: Double?
        let routine_day_id: UUID?
        let workout_choice_label: String?
        let is_rest_day: Bool
        let energy_level: Int?
        let soreness_level: Int?
        let yesterday_water_ml: Int?
        let yesterday_off_plan: Bool?
        let yesterday_off_plan_notes: String?
    }

    func fetch(date: Date) async throws -> DailyCheckin? {
        let checkins: [DailyCheckin] = try await client
            .from("daily_checkins")
            .select()
            .eq("checkin_date", value: DateFormatting.isoDate(date))
            .limit(1)
            .execute()
            .value
        return checkins.first
    }

    @discardableResult
    func save(
        date: Date,
        weightKg: Double?,
        routineDayId: UUID?,
        workoutChoiceLabel: String?,
        isRestDay: Bool,
        energyLevel: Int?,
        sorenessLevel: Int?,
        yesterdayWaterMl: Int?,
        yesterdayOffPlan: Bool?,
        yesterdayOffPlanNotes: String?
    ) async throws -> DailyCheckin {
        let userId = try await client.auth.session.user.id
        let payload = NewDailyCheckin(
            user_id: userId,
            checkin_date: DateFormatting.isoDate(date),
            weight_kg: weightKg,
            routine_day_id: routineDayId,
            workout_choice_label: workoutChoiceLabel,
            is_rest_day: isRestDay,
            energy_level: energyLevel,
            soreness_level: sorenessLevel,
            yesterday_water_ml: yesterdayWaterMl,
            yesterday_off_plan: yesterdayOffPlan,
            yesterday_off_plan_notes: yesterdayOffPlanNotes
        )
        let saved: [DailyCheckin] = try await client
            .from("daily_checkins")
            .upsert(payload, onConflict: "user_id,checkin_date")
            .select()
            .execute()
            .value
        guard let checkin = saved.first else {
            throw RepositoryError.insertFailed
        }
        return checkin
    }
}
