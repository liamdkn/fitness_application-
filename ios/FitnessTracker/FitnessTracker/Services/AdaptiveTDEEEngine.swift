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
    private static let minNutritionLogs = 8

    /// Cap on how far a single recommendation can move the target from the
    /// current one, so one noisy window can't whipsaw the user's calories.
    private static let maxStepKcal = 150.0

    /// How many days after a flagged off-plan day a water-weight bump can
    /// still be showing on the scale - matches `OffPlanWeightAdvisor`'s own
    /// "typically water weight, settles in 2-3 days" framing. Weigh-ins
    /// logged in this window are excluded from the trend calculation below
    /// (see `offPlanBumpDates`) rather than read as real weight change,
    /// since a single inflated reading at the end of the window would
    /// otherwise leak straight into `changePerWeek` and throw off the
    /// whole TDEE estimate.
    private static let offPlanBumpSettleDays = 3

    static func evaluate(
        weightLogs: [BodyWeightLog],
        nutritionLogs: [NutritionLog],
        recentCheckins: [DailyCheckin],
        goal: UserGoal,
        windowDays: Int = 21,
        asOf: Date = Date()
    ) -> TDEERecommendation? {
        let calendar = Calendar.current
        guard let windowStart = calendar.date(byAdding: .day, value: -windowDays, to: asOf) else { return nil }

        // Trend weight via EWMA (`TrendWeightCalculator`, shared with the
        // Dashboard's weight chart) - only updates on days with an actual
        // weigh-in, with the effective smoothing widened for gaps so a
        // week without a weigh-in doesn't mute the next reading. Bump-day
        // weigh-ins are dropped first so a temporary off-plan spike can't
        // pose as real weight change.
        let bumpDates = offPlanBumpDates(from: recentCheckins)
        let cleanedWeightLogs = weightLogs.filter { !bumpDates.contains(calendar.startOfDay(for: $0.loggedAt)) }
        let trendPoints = TrendWeightCalculator.compute(from: cleanedWeightLogs.filter { $0.loggedAt >= windowStart && $0.loggedAt <= asOf })
        let nutritionInWindow = nutritionLogs.filter { log in
            guard let date = DateFormatting.date(fromISODate: log.date) else { return false }
            return date >= windowStart && date <= asOf
        }

        guard trendPoints.count >= minWeighIns, nutritionInWindow.count >= minNutritionLogs else { return nil }
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
            recommendedCalorieTarget: recommended
        )
    }

    /// Every calendar day a water-weight bump from a flagged off-plan day
    /// could still be showing on the scale - the day of the check-in that
    /// reported it (`yesterdayOffPlan`, so the morning after the off-plan
    /// day itself) through `offPlanBumpSettleDays` later. The off-plan
    /// day's own weigh-in isn't included - it predates that day's eating.
    private static func offPlanBumpDates(from checkins: [DailyCheckin]) -> Set<Date> {
        let calendar = Calendar.current
        var dates: Set<Date> = []
        for checkin in checkins {
            guard checkin.yesterdayOffPlan == true,
                  let checkinDate = DateFormatting.date(fromISODate: checkin.checkinDate)
            else { continue }
            for offset in 0..<offPlanBumpSettleDays {
                if let bumpDate = calendar.date(byAdding: .day, value: offset, to: checkinDate) {
                    dates.insert(calendar.startOfDay(for: bumpDate))
                }
            }
        }
        return dates
    }
}
