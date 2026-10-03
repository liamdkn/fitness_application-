import Foundation

struct StepLog: Encodable {
    let userId: UUID
    let date: String
    let stepCount: Int
    let source: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case date
        case stepCount = "step_count"
        case source
    }
}

struct SleepLog: Encodable {
    let userId: UUID
    let date: String
    let totalSleepMinutes: Int
    let inBedMinutes: Int
    let source: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case date
        case totalSleepMinutes = "total_sleep_minutes"
        case inBedMinutes = "in_bed_minutes"
        case source
    }
}
