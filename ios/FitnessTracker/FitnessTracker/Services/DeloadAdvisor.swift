import Foundation

enum DeloadSeverity {
    case none, consider, recommended
}

struct DeloadSignal {
    let reasons: [String]
    let severity: DeloadSeverity
}

/// Looks for a *convergence* of accumulated-fatigue signals over a trailing
/// window - rising soreness, falling energy (both from daily check-ins),
/// and falling self-rated workout quality - rather than reacting to any
/// single data point. Purely advisory: never changes a routine on its own.
enum DeloadAdvisor {
    static func evaluate(recentCheckins: [DailyCheckin], recentWorkouts: [Workout]) -> DeloadSignal {
        var reasons: [String] = []

        let sorenessLevels = recentCheckins.compactMap(\.sorenessLevel)
        let energyLevels = recentCheckins.compactMap(\.energyLevel)
        let ratings = recentWorkouts.compactMap(\.rating)

        if sorenessLevels.count >= 4 {
            let recentAvg = average(Array(sorenessLevels.suffix(3)))
            let priorAvg = average(Array(sorenessLevels.dropLast(3)))
            if recentAvg - priorAvg >= 1.0 && recentAvg >= 3.5 {
                reasons.append("Soreness has been trending up")
            }
        }

        if energyLevels.count >= 4 {
            let recentAvg = average(Array(energyLevels.suffix(3)))
            let priorAvg = average(Array(energyLevels.dropLast(3)))
            if priorAvg - recentAvg >= 1.0 && recentAvg <= 2.5 {
                reasons.append("Energy has been trending down")
            }
        }

        if ratings.count >= 3 {
            let recentAvg = average(Array(ratings.suffix(2)))
            if recentAvg <= 2.0 {
                reasons.append("Your last couple of workouts were rated low")
            }
        }

        let severity: DeloadSeverity
        switch reasons.count {
        case 0: severity = .none
        case 1: severity = .consider
        default: severity = .recommended
        }

        return DeloadSignal(reasons: reasons, severity: severity)
    }

    private static func average(_ values: [Int]) -> Double {
        guard !values.isEmpty else { return 0 }
        return Double(values.reduce(0, +)) / Double(values.count)
    }
}
