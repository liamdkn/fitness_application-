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

    private struct PauseUpdate: Encodable {
        let paused_at: Date
    }

    private struct ResumeUpdate: Encodable {
        let paused_at: Date?
        let paused_seconds: Int
    }

    private struct FinishUpdate: Encodable {
        let ended_at: Date
        let paused_at: Date?
        let paused_seconds: Int
        let steps_after: Int?
        let avg_heart_rate: Int
    }

    private struct FinishWithoutDetailsUpdate: Encodable {
        let ended_at: Date
        let paused_at: Date?
        let paused_seconds: Int
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
            try? await stepSessionRepository.logSession(date: session.startedAt, stepsBefore: stepsBefore, stepsAfter: stepsAfter)
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
            try? await stepSessionRepository.logSession(date: session.startedAt, stepsBefore: stepsBefore, stepsAfter: stepsAfter)
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
}
