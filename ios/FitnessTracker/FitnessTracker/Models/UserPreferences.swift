import Foundation

struct UserPreferences: Codable {
    let weeklyCheckinWeekday: Int
    let cardioStepExclusionEnabled: Bool
    let stepSource: StepSource
    let enabledCardioTypes: [String]
    let preferredGymId: UUID?
    let dailyWaterMlTargetMin: Int
    let dailyWaterMlTargetMax: Int
    /// Sodium and caffeine settings - what the sodium bar and caffeine curve
    /// are measured against (see `CaffeineModel`).
    var sodiumLimitMg: Int = 2300
    var caffeineLimitMg: Int = 400
    /// Minutes after midnight - 1350 = 22:30.
    var bedtimeMinutes: Int = 1350
    var caffeineHalfLifeHours: Double = 5
    var caffeineBedtimeTargetMg: Int = 50

    enum CodingKeys: String, CodingKey {
        case weeklyCheckinWeekday = "weekly_checkin_weekday"
        case cardioStepExclusionEnabled = "cardio_step_exclusion_enabled"
        case stepSource = "step_source"
        case enabledCardioTypes = "enabled_cardio_types"
        case preferredGymId = "preferred_gym_id"
        case dailyWaterMlTargetMin = "daily_water_ml_target_min"
        case dailyWaterMlTargetMax = "daily_water_ml_target_max"
        case sodiumLimitMg = "sodium_limit_mg"
        case caffeineLimitMg = "caffeine_limit_mg"
        case bedtimeMinutes = "bedtime_minutes"
        case caffeineHalfLifeHours = "caffeine_half_life_hours"
        case caffeineBedtimeTargetMg = "caffeine_bedtime_target_mg"
    }

    /// Older rows (and a missing row) simply lack the new columns -
    /// decoding falls back to the defaults rather than failing the whole read.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        weeklyCheckinWeekday = try c.decode(Int.self, forKey: .weeklyCheckinWeekday)
        cardioStepExclusionEnabled = try c.decode(Bool.self, forKey: .cardioStepExclusionEnabled)
        stepSource = try c.decode(StepSource.self, forKey: .stepSource)
        enabledCardioTypes = try c.decode([String].self, forKey: .enabledCardioTypes)
        preferredGymId = try c.decodeIfPresent(UUID.self, forKey: .preferredGymId)
        dailyWaterMlTargetMin = try c.decode(Int.self, forKey: .dailyWaterMlTargetMin)
        dailyWaterMlTargetMax = try c.decode(Int.self, forKey: .dailyWaterMlTargetMax)
        sodiumLimitMg = try c.decodeIfPresent(Int.self, forKey: .sodiumLimitMg) ?? 2300
        caffeineLimitMg = try c.decodeIfPresent(Int.self, forKey: .caffeineLimitMg) ?? 400
        bedtimeMinutes = try c.decodeIfPresent(Int.self, forKey: .bedtimeMinutes) ?? 1350
        caffeineHalfLifeHours = try c.decodeIfPresent(Double.self, forKey: .caffeineHalfLifeHours) ?? 5
        caffeineBedtimeTargetMg = try c.decodeIfPresent(Int.self, forKey: .caffeineBedtimeTargetMg) ?? 50
    }

    init(
        weeklyCheckinWeekday: Int,
        cardioStepExclusionEnabled: Bool,
        stepSource: StepSource,
        enabledCardioTypes: [String],
        preferredGymId: UUID?,
        dailyWaterMlTargetMin: Int,
        dailyWaterMlTargetMax: Int
    ) {
        self.weeklyCheckinWeekday = weeklyCheckinWeekday
        self.cardioStepExclusionEnabled = cardioStepExclusionEnabled
        self.stepSource = stepSource
        self.enabledCardioTypes = enabledCardioTypes
        self.preferredGymId = preferredGymId
        self.dailyWaterMlTargetMin = dailyWaterMlTargetMin
        self.dailyWaterMlTargetMax = dailyWaterMlTargetMax
    }
}
