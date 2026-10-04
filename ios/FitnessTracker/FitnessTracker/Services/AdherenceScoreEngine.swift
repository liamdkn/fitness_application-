import Foundation

/// Computes a 0-100 "how on-plan was this day" score against the current
/// phase's targets - a pure, side-effect-free calculator in the same style
/// as `AdaptiveTDEEEngine`/`DeloadAdvisor`. The caller (view model) is
/// responsible for fetching that day's nutrition log, step count, workout
/// status, and check-in.
enum AdherenceScoreEngine {
    /// Calories score full marks within this fraction of target, decaying
    /// linearly to zero at `caloriesZeroBandPct` away. Scored two-sided
    /// (unlike protein/steps) because under-eating target on a cut is its
    /// own adherence problem, not free progress.
    private static let caloriesFullBandPct = 0.05
    private static let caloriesZeroBandPct = 0.30

    static func dailyScore(
        date: Date,
        goal: UserGoal?,
        nutrition: NutritionLog?,
        steps: Int?,
        didWorkout: Bool,
        isRestDay: Bool?
    ) -> DailyAdherenceScore {
        DailyAdherenceScore(
            date: date,
            components: [
                caloriesComponent(nutrition: nutrition, goal: goal),
                proteinComponent(nutrition: nutrition, goal: goal),
                stepsComponent(steps: steps, goal: goal),
                trainingComponent(didWorkout: didWorkout, isRestDay: isRestDay)
            ]
        )
    }

    private static func caloriesComponent(nutrition: NutritionLog?, goal: UserGoal?) -> AdherenceComponentScore {
        guard let target = goal?.dailyCalorieTarget, target > 0, let nutrition else {
            return AdherenceComponentScore(component: .calories, score: nil, detail: "Not logged")
        }
        let pctOff = abs(nutrition.calories - target) / target
        let score = bandScore(pctOff: pctOff, fullBand: caloriesFullBandPct, zeroBand: caloriesZeroBandPct)
        return AdherenceComponentScore(
            component: .calories,
            score: score,
            detail: "\(Int(nutrition.calories))/\(Int(target)) kcal"
        )
    }

    /// One-sided: hitting or exceeding the protein target is never a
    /// problem, so only a shortfall costs points.
    private static func proteinComponent(nutrition: NutritionLog?, goal: UserGoal?) -> AdherenceComponentScore {
        guard let target = goal?.proteinGTarget, target > 0, let nutrition else {
            return AdherenceComponentScore(component: .protein, score: nil, detail: "Not logged")
        }
        return AdherenceComponentScore(
            component: .protein,
            score: oneSidedScore(actual: nutrition.proteinG, target: target),
            detail: "\(Int(nutrition.proteinG))/\(Int(target))g"
        )
    }

    /// One-sided, same reasoning as protein - more steps than target is
    /// fine.
    private static func stepsComponent(steps: Int?, goal: UserGoal?) -> AdherenceComponentScore {
        guard let target = goal?.stepTarget, target > 0, let steps else {
            return AdherenceComponentScore(component: .steps, score: nil, detail: "Not synced")
        }
        return AdherenceComponentScore(
            component: .steps,
            score: oneSidedScore(actual: Double(steps), target: Double(target)),
            detail: "\(steps)/\(target)"
        )
    }

    /// A logged workout is always a hit. Otherwise this only scores a miss
    /// when the day's check-in explicitly says it wasn't a planned rest day
    /// - a rest day, or a day with no check-in at all, is left out of the
    /// average rather than guessed at.
    private static func trainingComponent(didWorkout: Bool, isRestDay: Bool?) -> AdherenceComponentScore {
        if didWorkout {
            return AdherenceComponentScore(component: .training, score: 100, detail: "Workout logged")
        }
        switch isRestDay {
        case true:
            return AdherenceComponentScore(component: .training, score: nil, detail: "Rest day")
        case false:
            return AdherenceComponentScore(component: .training, score: 0, detail: "No workout logged")
        case nil:
            return AdherenceComponentScore(component: .training, score: nil, detail: "No check-in")
        }
    }

    /// 100 within `fullBand` of target, decaying linearly to 0 at
    /// `zeroBand` away, clamped on both ends.
    private static func bandScore(pctOff: Double, fullBand: Double, zeroBand: Double) -> Double {
        guard pctOff > fullBand else { return 100 }
        guard pctOff < zeroBand else { return 0 }
        let t = (pctOff - fullBand) / (zeroBand - fullBand)
        return 100 * (1 - t)
    }

    /// Hitting or exceeding target scores full marks; only a shortfall
    /// costs points. Shared by protein, steps, and the weekly training
    /// sessions-completed-vs-required score.
    private static func oneSidedScore(actual: Double, target: Double) -> Double {
        min(100, (actual / target) * 100)
    }

    /// Rolls a week's worth of `DailyAdherenceScore`s (one per day, in
    /// order) into a single weekly score. Calories/protein/steps are the
    /// average of each day's score for that component - consistent with
    /// how the daily score already treats a missing day (excluded, not
    /// zeroed). Training is scored differently: sessions actually
    /// completed against the phase's required-sessions-per-week (total
    /// minus optional), when the phase sets one - averaging the days'
    /// individual hit/miss/rest-day scores instead would let a run of
    /// un-checked-in days quietly opt out of the count rather than read as
    /// a missed session, understating a real shortfall.
    static func weeklyScore(
        dailyScores: [DailyAdherenceScore],
        sessionsCompleted: Int,
        requiredSessionsPerWeek: Int?,
        elapsedDaysCount: Int
    ) -> WeeklyAdherenceScore {
        func averaged(_ component: AdherenceComponent) -> AdherenceComponentScore {
            let scores = dailyScores.compactMap { day in
                day.components.first { $0.component == component }?.score
            }
            guard !scores.isEmpty else {
                return AdherenceComponentScore(component: component, score: nil, detail: "Not logged")
            }
            let avg = scores.reduce(0, +) / Double(scores.count)
            return AdherenceComponentScore(
                component: component,
                score: avg,
                detail: "\(scores.count) day\(scores.count == 1 ? "" : "s") logged"
            )
        }

        let trainingComponent: AdherenceComponentScore
        if let requiredSessionsPerWeek, requiredSessionsPerWeek > 0 {
            trainingComponent = AdherenceComponentScore(
                component: .training,
                score: oneSidedScore(actual: Double(sessionsCompleted), target: Double(requiredSessionsPerWeek)),
                detail: "\(sessionsCompleted)/\(requiredSessionsPerWeek) sessions"
            )
        } else {
            trainingComponent = averaged(.training)
        }

        return WeeklyAdherenceScore(
            dailyScores: dailyScores,
            components: [
                averaged(.calories),
                averaged(.protein),
                averaged(.steps),
                trainingComponent
            ],
            elapsedDaysCount: max(0, min(dailyScores.count, elapsedDaysCount))
        )
    }
}
