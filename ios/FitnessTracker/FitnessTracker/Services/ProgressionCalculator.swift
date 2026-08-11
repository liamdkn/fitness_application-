import Foundation

struct ProgressionSuggestion {
    let suggestedWeightKg: Double?
    let targetReps: Int
    let note: String
}

enum ProgressionCalculator {
    /// Double progression: once every working set from last time hit the top
    /// of the rep range, suggest adding weight and dropping back to the
    /// bottom of the range. Otherwise keep the same weight and aim for the
    /// top of the range.
    static func suggest(previousSets: [WorkoutSet], target: RoutineDayExercise) -> ProgressionSuggestion {
        guard !previousSets.isEmpty else {
            return ProgressionSuggestion(
                suggestedWeightKg: nil,
                targetReps: target.repRangeLow,
                note: "First time logging this - pick a starting weight."
            )
        }

        let lastWeight = previousSets.map(\.weightKg).max() ?? 0
        let allHitTop = previousSets.allSatisfy { $0.reps >= target.repRangeHigh }

        if allHitTop {
            return ProgressionSuggestion(
                suggestedWeightKg: lastWeight + target.weightIncrementKg,
                targetReps: target.repRangeLow,
                note: "Hit \(target.repRangeHigh) reps on every set last time - go up in weight."
            )
        } else {
            return ProgressionSuggestion(
                suggestedWeightKg: lastWeight,
                targetReps: target.repRangeHigh,
                note: "Same weight as last time - push for \(target.repRangeHigh) reps on every set."
            )
        }
    }
}
