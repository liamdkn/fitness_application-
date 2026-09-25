import Foundation
import Supabase

struct WeeklyScheduleRepository {
    let client = SupabaseService.shared.client

    private struct NewSlot: Encodable {
        let user_id: UUID
        let routine_id: UUID
        let weekday: Int
    }

    // Manually implements `encode(to:)` because the auto-synthesized conformance
    // uses `encodeIfPresent` for Optional properties, which OMITS the JSON key
    // entirely when a value is nil - an update that clears routine_day_id (e.g.
    // switching a day from Workout to Rest) or cardio_type (switching away from
    // Active Rest) needs that key sent as an explicit null, or the column just
    // keeps its old value. Same fix `DailyCheckinRepository`/
    // `CardioSessionRepository` already use for this reason.
    private struct SlotUpdate: Encodable {
        let day_type: String
        let routine_day_id: UUID?
        let cardio_type: String?

        enum CodingKeys: String, CodingKey { case day_type, routine_day_id, cardio_type }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(day_type, forKey: .day_type)
            try container.encode(routine_day_id, forKey: .routine_day_id)
            try container.encode(cardio_type, forKey: .cardio_type)
        }
    }

    /// Every weekday slot for this routine, Sunday first - inserts any
    /// missing weekday (defaulting to `rest`) before returning, so a
    /// routine that predates this feature (or just had a slot deleted)
    /// always comes back with exactly 7 rows rather than making every
    /// caller handle a partial week.
    func fetchSchedule(routineId: UUID) async throws -> [WeeklyScheduleDay] {
        var days: [WeeklyScheduleDay] = try await client
            .from("weekly_schedule")
            .select()
            .eq("routine_id", value: routineId)
            .order("weekday")
            .execute()
            .value

        let existingWeekdays = Set(days.map(\.weekday))
        let missingWeekdays = (1...7).filter { !existingWeekdays.contains($0) }
        if !missingWeekdays.isEmpty {
            let userId = try await client.auth.session.user.id
            let inserted: [WeeklyScheduleDay] = try await client
                .from("weekly_schedule")
                .insert(missingWeekdays.map { NewSlot(user_id: userId, routine_id: routineId, weekday: $0) })
                .select()
                .execute()
                .value
            days.append(contentsOf: inserted)
            days.sort { $0.weekday < $1.weekday }
        }
        return days
    }

    @discardableResult
    func setSlot(
        id: UUID,
        dayType: ScheduledDayType,
        routineDayId: UUID?,
        cardioType: CardioType?
    ) async throws -> WeeklyScheduleDay {
        let updated: [WeeklyScheduleDay] = try await client
            .from("weekly_schedule")
            .update(SlotUpdate(day_type: dayType.rawValue, routine_day_id: routineDayId, cardio_type: cardioType?.rawValue))
            .eq("id", value: id)
            .select()
            .execute()
            .value
        guard let day = updated.first else {
            throw RepositoryError.insertFailed
        }
        return day
    }
}
