import Foundation
import Supabase

struct MuscleGroupVolumeRepository {
    let client = SupabaseService.shared.client

    /// Weekly volume rows for roughly the trailing `weeks` weeks (including
    /// the current, in-progress week), across all muscle groups. Uses a
    /// plain day-count cutoff rather than trying to align to a calendar
    /// week boundary client-side - the exact week bucketing comes back
    /// from Postgres in `week_start` regardless, so this only needs to be
    /// generous enough to include the weeks we want.
    func fetchRecentWeeks(weeks: Int = 6) async throws -> [MuscleGroupWeeklyVolume] {
        let calendar = Calendar.current
        let since = calendar.date(byAdding: .day, value: -(weeks * 7), to: Date()) ?? Date()
        return try await client
            .from("v_muscle_group_weekly_volume")
            .select()
            .gte("week_start", value: DateFormatting.isoDate(since))
            .order("week_start")
            .execute()
            .value
    }
}
