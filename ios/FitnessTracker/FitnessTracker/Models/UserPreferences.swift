import Foundation

struct UserPreferences: Codable {
    let weeklyCheckinWeekday: Int
    let cardioStepExclusionEnabled: Bool
    let stepSource: StepSource
    let enabledCardioTypes: [String]
    let preferredGymId: UUID?
    let dailyWaterMlTargetMin: Int
    let dailyWaterMlTargetMax: Int

    enum CodingKeys: String, CodingKey {
        case weeklyCheckinWeekday = "weekly_checkin_weekday"
        case cardioStepExclusionEnabled = "cardio_step_exclusion_enabled"
        case stepSource = "step_source"
        case enabledCardioTypes = "enabled_cardio_types"
        case preferredGymId = "preferred_gym_id"
        case dailyWaterMlTargetMin = "daily_water_ml_target_min"
        case dailyWaterMlTargetMax = "daily_water_ml_target_max"
    }
}
