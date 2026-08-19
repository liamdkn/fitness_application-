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
    }

    var isPaused: Bool { pausedAt != nil }

    func elapsed(asOf now: Date = Date()) -> TimeInterval {
        let end = endedAt ?? (pausedAt ?? now)
        return end.timeIntervalSince(startedAt) - Double(pausedSeconds)
    }
}
