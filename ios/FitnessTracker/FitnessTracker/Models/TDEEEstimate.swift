import Foundation

enum TDEEEstimateStatus: String, Codable {
    case pending, accepted, dismissed
}

struct TDEEEstimate: Codable, Identifiable, Hashable {
    let id: UUID
    let estimatedAt: String
    let windowDays: Int
    let loggedDaysInWindow: Int
    let avgDailyCalories: Double
    let trendWeightChangeKgPerWeek: Double
    let estimatedTDEE: Double
    let currentCalorieTarget: Double
    let recommendedCalorieTarget: Double
    let status: TDEEEstimateStatus

    enum CodingKeys: String, CodingKey {
        case id
        case estimatedAt = "estimated_at"
        case windowDays = "window_days"
        case loggedDaysInWindow = "logged_days_in_window"
        case avgDailyCalories = "avg_daily_calories"
        case trendWeightChangeKgPerWeek = "trend_weight_change_kg_per_week"
        case estimatedTDEE = "estimated_tdee"
        case currentCalorieTarget = "current_calorie_target"
        case recommendedCalorieTarget = "recommended_calorie_target"
        case status
    }
}
