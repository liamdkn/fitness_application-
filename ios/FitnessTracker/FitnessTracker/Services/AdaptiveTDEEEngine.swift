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
    /// deficit/surplus.
    private static let kcalPerKg = 7700.0

    /// EWMA smoothing rate for a single-day gap between weigh-ins; scaled
    /// up for longer gaps so the trend still converges reasonably fast
    /// (Hacker's-Diet-style trend weight).
    private static let baseAlpha = 0.1

    /// Minimum data before an estimate is trustworthy enough to show.
    private static let minWeighIns = 8
    private static let minNutritionLogs = 8

    /// Cap on how far a single recommendation can move the target from the
    /// current one, so one noisy window can't whipsaw the user's calories.
    private static let maxStepKcal = 150.0

    static func evaluate(
        weightLogs: [BodyWeightLog],
        nutritionLogs: [NutritionLog],
        goal: UserGoal,
        windowDays: Int = 21,
        asOf: Date = Date()
    ) -> TDEERecommendation? {
        let calendar = Calendar.current
        guard let windowStart = calendar.date(byAdding: .day, value: -windowDays, to: asOf) else { return nil }

        let dailyWeights = averagedByDay(weightLogs.filter { $0.loggedAt >= windowStart && $0.loggedAt <= asOf })
        let nutritionInWindow = nutritionLogs.filter { log in
            guard let date = DateFormatting.date(fromISODate: log.date) else { return false }
            return date >= windowStart && date <= asOf
        }

        guard dailyWeights.count >= minWeighIns, nutritionInWindow.count >= minNutritionLogs else { return nil }

        let sortedWeights = dailyWeights.sorted { $0.date < $1.date }
        guard let first = sortedWeights.first, let last = sortedWeights.last, last.date > first.date else { return nil }

        // Trend weight via EWMA: only updates on days with an actual
        // weigh-in, with the effective smoothing widened for gaps so a
        // week without a weigh-in doesn't mute the next reading.
        var trend = first.weightKg
        var previousDate = first.date
        for point in sortedWeights.dropFirst() {
            let gapDays = max(calendar.dateComponents([.day], from: previousDate, to: point.date).day ?? 1, 1)
            let alpha = 1 - pow(1 - baseAlpha, Double(gapDays))
            trend += alpha * (point.weightKg - trend)
            previousDate = point.date
        }

        let totalDays = Double(calendar.dateComponents([.day], from: first.date, to: last.date).day ?? 0)
        guard totalDays > 0 else { return nil }
        let changePerWeek = (trend - first.weightKg) / (totalDays / 7.0)

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

    private struct DailyWeight {
        let date: Date
        let weightKg: Double
    }

    private static func averagedByDay(_ logs: [BodyWeightLog]) -> [DailyWeight] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: logs) { calendar.startOfDay(for: $0.loggedAt) }
        return grouped.map { day, logsForDay in
            DailyWeight(date: day, weightKg: logsForDay.reduce(0) { $0 + $1.weightKg } / Double(logsForDay.count))
        }
    }
}
