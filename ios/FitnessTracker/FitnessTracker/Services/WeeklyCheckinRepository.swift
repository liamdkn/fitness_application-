import Foundation
import Supabase

struct WeeklyCheckinRepository {
    let client = SupabaseService.shared.client

    private struct NewWeeklyCheckin: Encodable {
        let user_id: UUID
        let goal_id: UUID?
        let checkin_date: String
        let week_number: Int?
        let overall_rating_7d: Int?
        let weight_kg: Double?
        let energy_level: Int?
        let soreness_level: Int?
        let stress_level: Int?
        let stress_reason: String?
        let biggest_win: String?
        let mood_notes: String?
        let overall_adherence: Int?
        let training_adherence: Int?
        let nutrition_adherence: Int?
        let discipline_level: Int?
        let upcoming_distractions: String?
    }

    func fetch(date: Date) async throws -> WeeklyCheckin? {
        let checkins: [WeeklyCheckin] = try await client
            .from("weekly_checkins")
            .select()
            .eq("checkin_date", value: DateFormatting.isoDate(date))
            .limit(1)
            .execute()
            .value
        return checkins.first
    }

    /// Whether a check-in has been completed at any point since `date`
    /// (e.g. since the start of the current check-in week) - the user may
    /// complete it a day or two after the scheduled weekday.
    func hasCheckinSince(_ date: Date) async throws -> Bool {
        let checkins: [WeeklyCheckin] = try await client
            .from("weekly_checkins")
            .select()
            .gte("checkin_date", value: DateFormatting.isoDate(date))
            .limit(1)
            .execute()
            .value
        return !checkins.isEmpty
    }

    /// Reverse-chronological page of check-ins for the history list under
    /// Settings - unlike `fetchRange`, this doesn't need a known date
    /// window up front.
    func fetchRecent(limit: Int = 52) async throws -> [WeeklyCheckin] {
        try await client
            .from("weekly_checkins")
            .select()
            .order("checkin_date", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    func fetchMostRecent() async throws -> WeeklyCheckin? {
        let checkins: [WeeklyCheckin] = try await client
            .from("weekly_checkins")
            .select()
            .order("checkin_date", ascending: false)
            .limit(1)
            .execute()
            .value
        return checkins.first
    }

    /// Check-ins within an inclusive calendar range, most recent first -
    /// lets Weekly Insights show whichever weekly check-in was filled in
    /// for the selected week, even if it landed a day or two after the
    /// week's official start (mirrors `DailyCheckinRepository.fetchRange`).
    func fetchRange(from: Date, to: Date) async throws -> [WeeklyCheckin] {
        try await client
            .from("weekly_checkins")
            .select()
            .gte("checkin_date", value: DateFormatting.isoDate(from))
            .lte("checkin_date", value: DateFormatting.isoDate(to))
            .order("checkin_date", ascending: false)
            .execute()
            .value
    }

    @discardableResult
    func save(
        date: Date,
        goalId: UUID?,
        weekNumber: Int?,
        overallRating7d: Int?,
        weightKg: Double?,
        energyLevel: Int?,
        sorenessLevel: Int?,
        stressLevel: Int?,
        stressReason: String?,
        biggestWin: String?,
        moodNotes: String?,
        overallAdherence: Int?,
        trainingAdherence: Int?,
        nutritionAdherence: Int?,
        disciplineLevel: Int?,
        upcomingDistractions: String?
    ) async throws -> WeeklyCheckin {
        let userId = try await client.auth.session.user.id
        let payload = NewWeeklyCheckin(
            user_id: userId,
            goal_id: goalId,
            checkin_date: DateFormatting.isoDate(date),
            week_number: weekNumber,
            overall_rating_7d: overallRating7d,
            weight_kg: weightKg,
            energy_level: energyLevel,
            soreness_level: sorenessLevel,
            stress_level: stressLevel,
            stress_reason: stressReason,
            biggest_win: biggestWin,
            mood_notes: moodNotes,
            overall_adherence: overallAdherence,
            training_adherence: trainingAdherence,
            nutrition_adherence: nutritionAdherence,
            discipline_level: disciplineLevel,
            upcoming_distractions: upcomingDistractions
        )
        let saved: [WeeklyCheckin] = try await client
            .from("weekly_checkins")
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
