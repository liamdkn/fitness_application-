import Foundation
import Supabase

struct CardioSessionRepository {
    let client = SupabaseService.shared.client
    private let stepSessionRepository = CardioStepSessionRepository()

    private struct NewCardioSession: Encodable {
        let user_id: UUID
        let cardio_type: String
        let steps_before: Int?
    }

    /// A Watch-recorded session imports as already-finished - unlike
    /// `NewCardioSession`, there's no live start/pause/finish lifecycle to
    /// go through, the Watch already has the whole thing.
    private struct NewHealthKitCardioSession: Encodable {
        let user_id: UUID
        let cardio_type: String
        let started_at: Date
        let ended_at: Date
        let avg_heart_rate: Int?
        let active_calories: Double?
        let distance_meters: Double?
        let elevation_gain_m: Double?
        let avg_power_w: Int?
        let avg_cadence_spm: Int?
        let total_calories: Double?
        let has_route: Bool
        let source: String
        let healthkit_uuid: String
    }

    private struct NewRunRoute: Encodable {
        let session_id: UUID
        let user_id: UUID
        let points: [RoutePoint]
    }

    /// Only the fields being filled in - nil ones are skipped, so a backfill
    /// never overwrites something already stored.
    private struct RunMetricsUpdate: Encodable {
        let distance_meters: Double?
        let elevation_gain_m: Double?
        let avg_power_w: Int?
        let avg_cadence_spm: Int?
        let total_calories: Double?
        let has_route: Bool?
    }

    private struct PauseUpdate: Encodable {
        let paused_at: Date
    }

    // These three manually implement `encode(to:)` because the auto-synthesized
    // conformance uses `encodeIfPresent` for Optional properties, which OMITS
    // the JSON key entirely when a value is nil - Supabase's update only touches
    // columns present in the request body, so `paused_at: nil` here would leave
    // the row's existing (non-null) paused_at untouched instead of clearing it,
    // which is exactly what resuming/finishing a paused session needs to do
    // (and finishing while still marked paused_at violates the DB's
    // `ended_at IS NULL OR paused_at IS NULL` check constraint). Same fix
    // `DailyCheckinRepository.NewDailyCheckin` already uses for this reason.
    private struct ResumeUpdate: Encodable {
        let paused_at: Date?
        let paused_seconds: Int

        enum CodingKeys: String, CodingKey { case paused_at, paused_seconds }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(paused_at, forKey: .paused_at)
            try container.encode(paused_seconds, forKey: .paused_seconds)
        }
    }

    private struct FinishUpdate: Encodable {
        let ended_at: Date
        let paused_at: Date?
        let paused_seconds: Int
        let steps_after: Int?
        let avg_heart_rate: Int

        enum CodingKeys: String, CodingKey { case ended_at, paused_at, paused_seconds, steps_after, avg_heart_rate }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(ended_at, forKey: .ended_at)
            try container.encode(paused_at, forKey: .paused_at)
            try container.encode(paused_seconds, forKey: .paused_seconds)
            try container.encode(steps_after, forKey: .steps_after)
            try container.encode(avg_heart_rate, forKey: .avg_heart_rate)
        }
    }

    private struct FinishWithoutDetailsUpdate: Encodable {
        let ended_at: Date
        let paused_at: Date?
        let paused_seconds: Int

        enum CodingKeys: String, CodingKey { case ended_at, paused_at, paused_seconds }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(ended_at, forKey: .ended_at)
            try container.encode(paused_at, forKey: .paused_at)
            try container.encode(paused_seconds, forKey: .paused_seconds)
        }
    }

    private struct DetailsUpdate: Encodable {
        let steps_after: Int?
        let avg_heart_rate: Int
    }

    func startSession(cardioType: CardioType, stepsBefore: Int?) async throws -> CardioTrackingSession {
        let userId = try await client.auth.session.user.id
        let inserted: [CardioTrackingSession] = try await client
            .from("cardio_tracking_sessions")
            .insert(NewCardioSession(user_id: userId, cardio_type: cardioType.rawValue, steps_before: stepsBefore))
            .select()
            .execute()
            .value
        guard let session = inserted.first else {
            throw RepositoryError.insertFailed
        }
        return session
    }

    /// Only ever called after the user confirms importing a specific
    /// detected Watch workout (see `WatchActivityViewModel`) - never from
    /// the background health sync, which only reads/detects, never writes
    /// a cardio session on its own.
    @discardableResult
    func importFromHealthKit(
        cardioType: CardioType,
        startedAt: Date,
        endedAt: Date,
        avgHeartRate: Int?,
        activeCalories: Double?,
        distanceMeters: Double? = nil,
        elevationGainM: Double? = nil,
        avgPowerW: Int? = nil,
        avgCadenceSPM: Int? = nil,
        totalCalories: Double? = nil,
        route: [RoutePoint] = [],
        healthkitUUID: String
    ) async throws -> CardioTrackingSession {
        let userId = try await client.auth.session.user.id
        let inserted: [CardioTrackingSession] = try await client
            .from("cardio_tracking_sessions")
            .insert(NewHealthKitCardioSession(
                user_id: userId,
                cardio_type: cardioType.rawValue,
                started_at: startedAt,
                ended_at: endedAt,
                avg_heart_rate: avgHeartRate,
                active_calories: activeCalories,
                distance_meters: distanceMeters,
                elevation_gain_m: elevationGainM,
                avg_power_w: avgPowerW,
                avg_cadence_spm: avgCadenceSPM,
                total_calories: totalCalories,
                has_route: !route.isEmpty,
                source: "healthkit",
                healthkit_uuid: healthkitUUID
            ))
            .select()
            .execute()
            .value
        guard let session = inserted.first else {
            throw RepositoryError.insertFailed
        }
        if !route.isEmpty {
            try await saveRoute(sessionId: session.id, userId: userId, points: route)
        }
        return session
    }

    private func saveRoute(sessionId: UUID, userId: UUID, points: [RoutePoint]) async throws {
        try await client
            .from("run_routes")
            .upsert(NewRunRoute(session_id: sessionId, user_id: userId, points: points), onConflict: "session_id")
            .execute()
    }

    func fetchRoute(sessionId: UUID) async throws -> [RoutePoint] {
        struct Row: Decodable { let points: [RoutePoint] }
        let rows: [Row] = try await client
            .from("run_routes")
            .select("points")
            .eq("session_id", value: sessionId)
            .limit(1)
            .execute()
            .value
        return rows.first?.points ?? []
    }

    /// Fills the run extras (and route) onto a run imported before they were
    /// being read.
    func enrichRun(
        sessionId: UUID,
        distanceMeters: Double?,
        elevationGainM: Double?,
        avgPowerW: Int?,
        avgCadenceSPM: Int?,
        totalCalories: Double?,
        route: [RoutePoint]
    ) async throws {
        let userId = try await client.auth.session.user.id
        try await client
            .from("cardio_tracking_sessions")
            .update(RunMetricsUpdate(
                distance_meters: distanceMeters,
                elevation_gain_m: elevationGainM,
                avg_power_w: avgPowerW,
                avg_cadence_spm: avgCadenceSPM,
                total_calories: totalCalories,
                has_route: route.isEmpty ? nil : true
            ))
            .eq("id", value: sessionId)
            .execute()
        if !route.isEmpty {
            try await saveRoute(sessionId: sessionId, userId: userId, points: route)
        }
    }

    func pauseSession(sessionId: UUID) async throws -> CardioTrackingSession {
        let updated: [CardioTrackingSession] = try await client
            .from("cardio_tracking_sessions")
            .update(PauseUpdate(paused_at: Date()))
            .eq("id", value: sessionId)
            .select()
            .execute()
            .value
        guard let session = updated.first else {
            throw RepositoryError.insertFailed
        }
        return session
    }

    func resumeSession(sessionId: UUID, newPausedSeconds: Int) async throws -> CardioTrackingSession {
        let updated: [CardioTrackingSession] = try await client
            .from("cardio_tracking_sessions")
            .update(ResumeUpdate(paused_at: nil, paused_seconds: newPausedSeconds))
            .eq("id", value: sessionId)
            .select()
            .execute()
            .value
        guard let session = updated.first else {
            throw RepositoryError.insertFailed
        }
        return session
    }

    @discardableResult
    func finishSession(
        sessionId: UUID,
        finalPausedSeconds: Int,
        stepsAfter: Int?,
        avgHeartRate: Int
    ) async throws -> CardioTrackingSession {
        let updated: [CardioTrackingSession] = try await client
            .from("cardio_tracking_sessions")
            .update(FinishUpdate(
                ended_at: Date(),
                paused_at: nil,
                paused_seconds: finalPausedSeconds,
                steps_after: stepsAfter,
                avg_heart_rate: avgHeartRate
            ))
            .eq("id", value: sessionId)
            .select()
            .execute()
            .value
        guard let session = updated.first else {
            throw RepositoryError.insertFailed
        }
        if let stepsBefore = session.stepsBefore, let stepsAfter {
            _ = try? await stepSessionRepository.logSession(date: session.startedAt, stepsBefore: stepsBefore, stepsAfter: stepsAfter)
        }
        return session
    }

    @discardableResult
    func finishSessionWithoutDetails(sessionId: UUID, finalPausedSeconds: Int) async throws -> CardioTrackingSession {
        let updated: [CardioTrackingSession] = try await client
            .from("cardio_tracking_sessions")
            .update(FinishWithoutDetailsUpdate(
                ended_at: Date(),
                paused_at: nil,
                paused_seconds: finalPausedSeconds
            ))
            .eq("id", value: sessionId)
            .select()
            .execute()
            .value
        guard let session = updated.first else {
            throw RepositoryError.insertFailed
        }
        return session
    }

    func discardSession(sessionId: UUID) async throws {
        try await client
            .from("cardio_tracking_sessions")
            .delete()
            .eq("id", value: sessionId)
            .execute()
    }

    @discardableResult
    func updateSessionDetails(sessionId: UUID, stepsAfter: Int?, avgHeartRate: Int) async throws -> CardioTrackingSession {
        let updated: [CardioTrackingSession] = try await client
            .from("cardio_tracking_sessions")
            .update(DetailsUpdate(steps_after: stepsAfter, avg_heart_rate: avgHeartRate))
            .eq("id", value: sessionId)
            .select()
            .execute()
            .value
        guard let session = updated.first else {
            throw RepositoryError.insertFailed
        }
        if let stepsBefore = session.stepsBefore, let stepsAfter {
            _ = try? await stepSessionRepository.logSession(date: session.startedAt, stepsBefore: stepsBefore, stepsAfter: stepsAfter)
        }
        return session
    }

    func fetchActive() async throws -> CardioTrackingSession? {
        let sessions: [CardioTrackingSession] = try await client
            .from("cardio_tracking_sessions")
            .select()
            .is("ended_at", value: nil)
            .order("started_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return sessions.first
    }

    func fetchHistory(limit: Int = 50) async throws -> [CardioTrackingSession] {
        try await client
            .from("cardio_tracking_sessions")
            .select()
            .order("started_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    /// Range-filtered at the DB level, unlike `fetchHistory(limit:)` - lets
    /// Weekly Insights look at an arbitrary past week without needing that
    /// week to fall inside the most-recent-N sessions.
    func fetchHistory(from: Date, to: Date) async throws -> [CardioTrackingSession] {
        try await client
            .from("cardio_tracking_sessions")
            .select()
            .gte("started_at", value: from.ISO8601Format())
            .lte("started_at", value: to.ISO8601Format())
            .order("started_at")
            .execute()
            .value
    }
}
