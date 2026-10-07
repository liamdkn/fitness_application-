import Foundation
import Supabase

struct RunningPlanRepository {
    let client = SupabaseService.shared.client


    /// The pieces of a run beyond its date, type and basic targets.
    struct Segments {
        var warmupMin: Int?
        var warmupPaceSec: Int?
        var cooldownMin: Int?
        var cooldownPaceSec: Int?
        var warmupKm: Double?
        var cooldownKm: Double?
        var mainPaceSec: Int?
        var blocks: [RunBlock]?
        static let none = Segments()
    }

    private struct NewPlannedRun: Encodable {
        let running_plan_id: UUID
        let user_id: UUID
        let date: String
        let run_type: String
        let target_distance_km: Double?
        let target_duration_min: Int?
        let notes: String?
        let segments: Segments

        enum CodingKeys: String, CodingKey {
            case running_plan_id, user_id, date, run_type, target_distance_km, target_duration_min, notes
            case warmup_min, warmup_pace_sec, cooldown_min, cooldown_pace_sec, warmup_km, cooldown_km, main_pace_sec, blocks
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(running_plan_id, forKey: .running_plan_id)
            try c.encode(user_id, forKey: .user_id)
            try c.encode(date, forKey: .date)
            try c.encode(run_type, forKey: .run_type)
            try c.encode(target_distance_km, forKey: .target_distance_km)
            try c.encode(target_duration_min, forKey: .target_duration_min)
            try c.encode(notes, forKey: .notes)
            try c.encode(segments.warmupMin, forKey: .warmup_min)
            try c.encode(segments.warmupPaceSec, forKey: .warmup_pace_sec)
            try c.encode(segments.cooldownMin, forKey: .cooldown_min)
            try c.encode(segments.cooldownPaceSec, forKey: .cooldown_pace_sec)
            try c.encode(segments.warmupKm, forKey: .warmup_km)
            try c.encode(segments.cooldownKm, forKey: .cooldown_km)
            try c.encode(segments.mainPaceSec, forKey: .main_pace_sec)
            try c.encode(segments.blocks, forKey: .blocks)
        }
    }

    /// Every editable field sent in full, with the optional ones as
    /// explicit nulls (not skipped) so clearing a target actually clears it.
    private struct PlannedRunUpdate: Encodable {
        let date: String
        let run_type: String
        let target_distance_km: Double?
        let target_duration_min: Int?
        let notes: String?
        let segments: Segments

        enum CodingKeys: String, CodingKey {
            case date, run_type, target_distance_km, target_duration_min, notes
            case warmup_min, warmup_pace_sec, cooldown_min, cooldown_pace_sec, warmup_km, cooldown_km, main_pace_sec, blocks
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(date, forKey: .date)
            try c.encode(run_type, forKey: .run_type)
            try c.encode(target_distance_km, forKey: .target_distance_km)
            try c.encode(target_duration_min, forKey: .target_duration_min)
            try c.encode(notes, forKey: .notes)
            try c.encode(segments.warmupMin, forKey: .warmup_min)
            try c.encode(segments.warmupPaceSec, forKey: .warmup_pace_sec)
            try c.encode(segments.cooldownMin, forKey: .cooldown_min)
            try c.encode(segments.cooldownPaceSec, forKey: .cooldown_pace_sec)
            try c.encode(segments.warmupKm, forKey: .warmup_km)
            try c.encode(segments.cooldownKm, forKey: .cooldown_km)
            try c.encode(segments.mainPaceSec, forKey: .main_pace_sec)
            try c.encode(segments.blocks, forKey: .blocks)
        }
    }

    private struct NewRunningPlan: Encodable {
        let user_id: UUID
        let name: String
        let start_date: String
        let first_week_number: Int
    }

    @discardableResult
    func createPlan(name: String, startDate: Date, firstWeekNumber: Int) async throws -> RunningPlan {
        let userId = try await client.auth.session.user.id
        let inserted: [RunningPlan] = try await client
            .from("running_plans")
            .insert(NewRunningPlan(
                user_id: userId,
                name: name,
                start_date: DateFormatting.isoDate(startDate),
                first_week_number: firstWeekNumber
            ))
            .select()
            .execute()
            .value
        guard let plan = inserted.first else { throw RepositoryError.insertFailed }
        return plan
    }

    /// The most recently started plan - a person has one running plan at a
    /// time, so "latest start date" is the active one.
    func fetchActivePlan() async throws -> RunningPlan? {
        let plans: [RunningPlan] = try await client
            .from("running_plans")
            .select()
            .order("start_date", ascending: false)
            .limit(1)
            .execute()
            .value
        return plans.first
    }

    func fetchPlannedRuns(planId: UUID) async throws -> [PlannedRun] {
        try await client
            .from("planned_runs")
            .select()
            .eq("running_plan_id", value: planId)
            .order("date")
            .execute()
            .value
    }

    /// Imported Watch runs on or after `from` - outdoor runs, plus indoor
    /// ones only when they carry a distance (a treadmill walk isn't a run).
    func fetchRuns(from: Date) async throws -> [CardioTrackingSession] {
        let sessions: [CardioTrackingSession] = try await client
            .from("cardio_tracking_sessions")
            .select()
            .gte("started_at", value: from.ISO8601Format())
            .order("started_at")
            .execute()
            .value
        return sessions.filter {
            $0.endedAt != nil && ($0.cardioType == .outdoorRun || ($0.cardioType == .treadmill && ($0.distanceMeters ?? 0) > 0))
        }
    }

    @discardableResult
    func addRun(
        planId: UUID,
        date: Date,
        runType: RunType,
        targetDistanceKm: Double?,
        targetDurationMin: Int?,
        notes: String?,
        segments: Segments? = nil
    ) async throws -> PlannedRun {
        let segments = segments ?? Segments()
        let userId = try await client.auth.session.user.id
        let inserted: [PlannedRun] = try await client
            .from("planned_runs")
            .insert(NewPlannedRun(
                running_plan_id: planId,
                user_id: userId,
                date: DateFormatting.isoDate(date),
                run_type: runType.rawValue,
                target_distance_km: targetDistanceKm,
                target_duration_min: targetDurationMin,
                notes: notes,
                segments: segments
            ))
            .select()
            .execute()
            .value
        guard let run = inserted.first else { throw RepositoryError.insertFailed }
        return run
    }

    @discardableResult
    func updateRun(
        id: UUID,
        date: Date,
        runType: RunType,
        targetDistanceKm: Double?,
        targetDurationMin: Int?,
        notes: String?,
        segments: Segments? = nil
    ) async throws -> PlannedRun {
        let segments = segments ?? Segments()
        let updated: [PlannedRun] = try await client
            .from("planned_runs")
            .update(PlannedRunUpdate(
                date: DateFormatting.isoDate(date),
                run_type: runType.rawValue,
                target_distance_km: targetDistanceKm,
                target_duration_min: targetDurationMin,
                notes: notes,
                segments: segments
            ))
            .eq("id", value: id)
            .select()
            .execute()
            .value
        guard let run = updated.first else { throw RepositoryError.insertFailed }
        return run
    }

    func deleteRun(id: UUID) async throws {
        try await client
            .from("planned_runs")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}
