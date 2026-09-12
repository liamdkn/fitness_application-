import Foundation

enum NutritionSource: String, Codable {
    case inHouse = "in_house"
    case healthkitManual = "healthkit_manual"
}

struct UserPreferences: Codable {
    let weeklyCheckinWeekday: Int
    let cardioStepExclusionEnabled: Bool
    let stepSource: StepSource
    let enabledCardioTypes: [String]
    let nutritionSource: NutritionSource

    enum CodingKeys: String, CodingKey {
        case weeklyCheckinWeekday = "weekly_checkin_weekday"
        case cardioStepExclusionEnabled = "cardio_step_exclusion_enabled"
        case stepSource = "step_source"
        case enabledCardioTypes = "enabled_cardio_types"
        case nutritionSource = "nutrition_source"
    }
}
