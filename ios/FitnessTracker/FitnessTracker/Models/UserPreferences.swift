import Foundation

struct UserPreferences: Codable {
    let weeklyCheckinWeekday: Int
    let cardioStepExclusionEnabled: Bool

    enum CodingKeys: String, CodingKey {
        case weeklyCheckinWeekday = "weekly_checkin_weekday"
        case cardioStepExclusionEnabled = "cardio_step_exclusion_enabled"
    }
}
