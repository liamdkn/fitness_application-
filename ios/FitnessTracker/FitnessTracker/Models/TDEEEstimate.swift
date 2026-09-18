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
    /// Weigh-ins the underlying `TDEERecommendation` excluded as a
    /// post-off-plan water-weight bump - see
    /// `OffPlanWeightAdvisor.excludingBumpDates`. Decoded leniently
    /// (defaults to 0) so this still reads rows saved before the column
    /// existed.
    let excludedBumpDays: Int

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
        case excludedBumpDays = "excluded_bump_days"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        estimatedAt = try container.decode(String.self, forKey: .estimatedAt)
        windowDays = try container.decode(Int.self, forKey: .windowDays)
        loggedDaysInWindow = try container.decode(Int.self, forKey: .loggedDaysInWindow)
        avgDailyCalories = try container.decode(Double.self, forKey: .avgDailyCalories)
        trendWeightChangeKgPerWeek = try container.decode(Double.self, forKey: .trendWeightChangeKgPerWeek)
        estimatedTDEE = try container.decode(Double.self, forKey: .estimatedTDEE)
        currentCalorieTarget = try container.decode(Double.self, forKey: .currentCalorieTarget)
        recommendedCalorieTarget = try container.decode(Double.self, forKey: .recommendedCalorieTarget)
        status = try container.decode(TDEEEstimateStatus.self, forKey: .status)
        excludedBumpDays = try container.decodeIfPresent(Int.self, forKey: .excludedBumpDays) ?? 0
    }
}
