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
        case source
        case healthkitUUID = "healthkit_uuid"
    }

    var isPaused: Bool { pausedAt != nil }

    func elapsed(asOf now: Date = Date()) -> TimeInterval {
        let end = endedAt ?? (pausedAt ?? now)
        return end.timeIntervalSince(startedAt) - Double(pausedSeconds)
    }
}
