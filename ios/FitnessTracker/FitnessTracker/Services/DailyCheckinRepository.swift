import Foundation
import Supabase

struct DailyCheckinRepository {
    let client = SupabaseService.shared.client

    // Manually implements `encode(to:)` because the auto-synthesized conformance
    // uses `encodeIfPresent` for Optional properties, which OMITS the JSON key
    // entirely when a value is nil. Supabase's upsert only touches columns present
    // in the request body, so an omitted key leaves the existing row's value
    // untouched instead of clearing it (e.g. picking "Rest" wouldn't null out a
    // previously-saved routine_day_id). Encoding explicit `null`s fixes that.
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

        enum CodingKeys: String, CodingKey {
            case user_id, checkin_date, weight_kg, routine_day_id, workout_choice_label,
                 is_rest_day, energy_level, soreness_level, yesterday_water_ml,
                 yesterday_off_plan, yesterday_off_plan_notes
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(user_id, forKey: .user_id)
            try container.encode(checkin_date, forKey: .checkin_date)
            try container.encode(weight_kg, forKey: .weight_kg)
            try container.encode(routine_day_id, forKey: .routine_day_id)
            try container.encode(workout_choice_label, forKey: .workout_choice_label)
            try container.encode(is_rest_day, forKey: .is_rest_day)
            try container.encode(energy_level, forKey: .energy_level)
            try container.encode(soreness_level, forKey: .soreness_level)
            try container.encode(yesterday_water_ml, forKey: .yesterday_water_ml)
            try container.encode(yesterday_off_plan, forKey: .yesterday_off_plan)
            try container.encode(yesterday_off_plan_notes, forKey: .yesterday_off_plan_notes)
        }
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

    /// Check-ins from the trailing `days` calendar days, oldest first - used
    /// to look at energy/soreness trends (e.g. DeloadAdvisor) rather than a
    /// single day's reading.
    func fetchRecent(days: Int) async throws -> [DailyCheckin] {
        let calendar = Calendar.current
        let since = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return try await client
            .from("daily_checkins")
            .select()
            .gte("checkin_date", value: DateFormatting.isoDate(since))
            .order("checkin_date")
            .execute()
            .value
    }

    /// Check-ins within an inclusive calendar range, oldest first - mirrors
    /// `NutritionRepository.fetchRange`/`HealthRepository.fetchStepLogs`,
    /// used by the weekly adherence score to know which days were planned
    /// rest days.
    func fetchRange(from: Date, to: Date) async throws -> [DailyCheckin] {
        try await client
            .from("daily_checkins")
            .select()
            .gte("checkin_date", value: DateFormatting.isoDate(from))
            .lte("checkin_date", value: DateFormatting.isoDate(to))
            .order("checkin_date")
            .execute()
            .value
    }

    /// Every check-in that flagged the previous day as off-plan, oldest
    /// first - a targeted query rather than fetching full history and
    /// filtering client-side, since `OffPlanWeightAdvisor`'s historical
    /// stat wants every occurrence, not a recent window.
    func fetchOffPlanDays() async throws -> [DailyCheckin] {
        try await client
            .from("daily_checkins")
            .select()
            .eq("yesterday_off_plan", value: true)
            .order("checkin_date")
            .execute()
            .value
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
