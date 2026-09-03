import Foundation
import Supabase

struct BodyMeasurementRepository {
    let client = SupabaseService.shared.client

    private struct NewBodyMeasurement: Encodable {
        let user_id: UUID
        let measured_at: String
        let waist_cm: Double?
        let left_bicep_cm: Double?
        let right_bicep_cm: Double?
        let goal_id: UUID?
        let weekly_checkin_id: UUID?
        let source: String
    }

    func fetchRecent(limit: Int = 30) async throws -> [BodyMeasurement] {
        try await client
            .from("body_measurements")
            .select()
            .order("measured_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    /// Measurements logged against a specific weekly check-in - used by the
    /// check-in history/detail screen under Settings.
    func fetchForWeeklyCheckin(_ weeklyCheckinId: UUID) async throws -> [BodyMeasurement] {
        try await client
            .from("body_measurements")
            .select()
            .eq("weekly_checkin_id", value: weeklyCheckinId)
            .order("measured_at", ascending: false)
            .execute()
            .value
    }

    @discardableResult
    func log(
        waistCm: Double?,
        leftBicepCm: Double?,
        rightBicepCm: Double?,
        goalId: UUID?,
        weeklyCheckinId: UUID? = nil,
        source: String
    ) async throws -> BodyMeasurement {
        let userId = try await client.auth.session.user.id
        let inserted: [BodyMeasurement] = try await client
            .from("body_measurements")
            .insert(NewBodyMeasurement(
                user_id: userId,
                measured_at: DateFormatting.isoDate(Date()),
                waist_cm: waistCm,
                left_bicep_cm: leftBicepCm,
                right_bicep_cm: rightBicepCm,
                goal_id: goalId,
                weekly_checkin_id: weeklyCheckinId,
                source: source
            ))
            .select()
            .execute()
            .value
        guard let measurement = inserted.first else {
            throw RepositoryError.insertFailed
        }
        return measurement
    }
}
