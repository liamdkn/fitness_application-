import Foundation

struct CardioTrackingSession: Codable, Identifiable, Hashable {
    let id: UUID
    let cardioType: CardioType
    let startedAt: Date
    let endedAt: Date?
    let pausedAt: Date?
    let pausedSeconds: Int
    let stepsBefore: Int?
    let stepsAfter: Int?
    let avgHeartRate: Int?
    let activeCalories: Double?
    /// Distance in metres - only Watch imports carry one (the in-app live
    /// tracker never asks for it), and only runs use it today.
    let distanceMeters: Double?
    /// Run extras from the Watch - nil when it didn't record them, and for
    /// anything that isn't a Watch-imported run.
    let elevationGainM: Double?
    let avgPowerW: Int?
    let avgCadenceSPM: Int?
    /// Active + resting energy ("Total Calories"); `activeCalories` stays
    /// the active-only figure.
    let totalCalories: Double?
    /// Whether a GPS route is stored for this session (`run_routes`) - the
    /// route itself is fetched only when a run's detail screen opens.
    let hasRoute: Bool
    /// `"app"` for a session started/finished through this app's own live
    /// tracker, `"healthkit"` for one imported from a Watch-recorded
    /// workout (see `WatchActivityViewModel`) - only ever set at import
    /// time, never toggled after the fact.
    let source: String
    let healthkitUUID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case cardioType = "cardio_type"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case pausedAt = "paused_at"
        case pausedSeconds = "paused_seconds"
        case stepsBefore = "steps_before"
        case stepsAfter = "steps_after"
        case avgHeartRate = "avg_heart_rate"
        case activeCalories = "active_calories"
        case distanceMeters = "distance_meters"
        case elevationGainM = "elevation_gain_m"
        case avgPowerW = "avg_power_w"
        case avgCadenceSPM = "avg_cadence_spm"
        case totalCalories = "total_calories"
        case hasRoute = "has_route"
        case source
        case healthkitUUID = "healthkit_uuid"
    }

    var isPaused: Bool { pausedAt != nil }

    func elapsed(asOf now: Date = Date()) -> TimeInterval {
        let end = endedAt ?? (pausedAt ?? now)
        return end.timeIntervalSince(startedAt) - Double(pausedSeconds)
    }
}
