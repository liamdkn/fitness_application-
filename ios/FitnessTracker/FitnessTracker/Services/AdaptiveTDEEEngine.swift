import Foundation

/// A data-driven estimate of true daily energy expenditure and a
/// recommended calorie target, derived from the relationship between
/// logged intake and the underlying (noise-filtered) body-weight trend
/// over a trailing window - the same principle adaptive-TDEE trackers
/// like MacroFactor use: back-calculate expenditure from intake + trend
/// weight change, rather than guess it from a Mifflin-St Jeor-style formula.
struct TDEERecommendation {
    let windowDays: Int
    let loggedDaysInWindow: Int
    let avgDailyCalories: Double
    let trendWeightChangeKgPerWeek: Double
    let estimatedTDEE: Double
    let currentCalorieTarget: Double
    let recommendedCalorieTarget: Double

    /// Weigh-ins within the window excluded as a post-off-plan water-weight
    /// bump (see `OffPlanWeightAdvisor.excludingBumpDates`) - surfaced so
    /// the recommendation banner can say so rather than presenting the
    /// trend as if it read every logged weigh-in.
    let excludedBumpDays: Int

    /// Whether the recommended target differs enough from the current one
    /// to be worth surfacing - avoids nagging over rounding noise.
    var isActionable: Bool {
        abs(recommendedCalorieTarget - currentCalorieTarget) >= 75
    }
}

enum AdaptiveTDEEEngine {
    /// Kcal per kg of body-mass change. 7700 is the standard approximation
    /// (Wishnofsky) for a mix of fat and lean tissue change in a typical
    /// deficit/surplus. Not private - reused by WeeklyInsightsViewModel to
    /// translate a calorie surplus/deficit into an implied weekly weight
    /// change using the exact same constant.
    static let kcalPerKg = 7700.0

    /// Minimum data before an estimate is trustworthy enough to show.
    private static let minWeighIns = 8
    private static let minimumNutritionDaysPerWeek = 5

    /// Cap on how far a single recommendation can move the target from the
    /// current one, so one noisy window can't whipsaw the user's calories.
    private static let maxStepKcal = 150.0

    static func evaluate(
        weightLogs: [BodyWeightLog],
        nutritionLogs: [NutritionLog],
        recentCheckins: [DailyCheckin],
        goal: UserGoal,
        windowDays: Int = 21,
        asOf: Date = Date()
    ) -> TDEERecommendation? {
        let calendar = Calendar.current
        let windowEnd = calendar.startOfDay(for: asOf)
        guard let windowStart = calendar.date(byAdding: .day, value: -windowDays, to: windowEnd) else { return nil }

        // Trend weight via EWMA (`TrendWeightCalculator`, shared with the
        // Dashboard's weight chart) - only updates on days with an actual
        // weigh-in, with the effective smoothing widened for gaps so a
        // week without a weigh-in doesn't mute the next reading. Bump-day
        // weigh-ins are dropped first so a temporary off-plan spike can't
        // pose as real weight change.
        let weightLogsInWindow = weightLogs.filter { $0.loggedAt >= windowStart && $0.loggedAt < windowEnd }
        let (cleanedWeightLogsInWindow, excludedBumpDays) = OffPlanWeightAdvisor.excludingBumpDates(from: weightLogsInWindow, checkins: recentCheckins)
        let trendPoints = TrendWeightCalculator.compute(from: cleanedWeightLogsInWindow)
        let nutritionInWindow = nutritionLogs.filter { log in
            guard let date = DateFormatting.date(fromISODate: log.date) else { return false }
            return date >= windowStart && date < windowEnd
        }

        guard trendPoints.count >= minWeighIns,
              hasAdequateNutritionCoverage(nutritionInWindow, windowStart: windowStart, windowDays: windowDays, calendar: calendar)
        else { return nil }
        guard let first = trendPoints.first, let last = trendPoints.last, last.date > first.date else { return nil }

        let totalDays = Double(calendar.dateComponents([.day], from: first.date, to: last.date).day ?? 0)
        guard totalDays > 0 else { return nil }
        let changePerWeek = (last.weightKg - first.weightKg) / (totalDays / 7.0)

        let avgCalories = nutritionInWindow.reduce(0.0) { $0 + $1.calories } / Double(nutritionInWindow.count)
        let dailyBalance = changePerWeek * kcalPerKg / 7.0
        let estimatedTDEE = avgCalories - dailyBalance

        let targetWeeklyChange = goal.weeklyWeightChangeKg ?? 0
        let targetDailyBalance = targetWeeklyChange * kcalPerKg / 7.0
        let rawRecommendation = estimatedTDEE + targetDailyBalance

        let delta = rawRecommendation - goal.dailyCalorieTarget
        let cappedDelta = max(-maxStepKcal, min(maxStepKcal, delta))
        let recommended = ((goal.dailyCalorieTarget + cappedDelta) / 10).rounded(.toNearestOrAwayFromZero) * 10

        return TDEERecommendation(
            windowDays: windowDays,
            loggedDaysInWindow: nutritionInWindow.count,
            avgDailyCalories: avgCalories,
            trendWeightChangeKgPerWeek: changePerWeek,
            estimatedTDEE: estimatedTDEE,
            currentCalorieTarget: goal.dailyCalorieTarget,
            recommendedCalorieTarget: recommended,
            excludedBumpDays: excludedBumpDays
        )
    }

    /// Averages over only logged days can look dramatically better when
    /// missed days include untracked overeating. Require broad coverage and
    /// coverage in each week-sized segment before using that average to
    /// estimate expenditure. Missing days stay unknown; they are never
    /// imputed as zero calories.
    private static func hasAdequateNutritionCoverage(
        _ logs: [NutritionLog],
        windowStart: Date,
        windowDays: Int,
        calendar: Calendar
    ) -> Bool {
        guard windowDays > 0 else { return false }
        let loggedDates = Set(logs.compactMap { log -> Date? in
            guard let date = DateFormatting.date(fromISODate: log.date) else { return nil }
            return calendar.startOfDay(for: date)
        })

        var offset = 0
        while offset < windowDays {
            let segmentLength = min(7, windowDays - offset)
            guard let segmentStart = calendar.date(byAdding: .day, value: offset, to: windowStart),
                  let segmentEnd = calendar.date(byAdding: .day, value: segmentLength, to: segmentStart)
            else { return false }
            let count = loggedDates.filter { $0 >= segmentStart && $0 < segmentEnd }.count
            let required = Int(ceil(Double(segmentLength) * Double(minimumNutritionDaysPerWeek) / 7.0))
            guard count >= required else { return false }
            offset += segmentLength
        }
        return true
    }
}
