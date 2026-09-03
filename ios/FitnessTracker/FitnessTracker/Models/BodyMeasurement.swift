import Foundation

struct BodyMeasurement: Codable, Identifiable {
    let id: UUID
    let measuredAt: String
    let waistCm: Double?
    let leftBicepCm: Double?
    let rightBicepCm: Double?
    let source: String
    let weeklyCheckinId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case measuredAt = "measured_at"
        case waistCm = "waist_cm"
        case leftBicepCm = "left_bicep_cm"
        case rightBicepCm = "right_bicep_cm"
        case source
        case weeklyCheckinId = "weekly_checkin_id"
    }
}
