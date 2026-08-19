import Foundation

struct ProgressionSuggestion {
    let suggestedWeightKg: Double?
    let targetReps: Int
    let note: String
}

enum ProgressionCalculator {
    /// Double progression, autoregulated by RPE when it's available: once
    /// every working set from last time hit the top of the rep range,
    /// suggest adding weight and dropping back to the bottom of the range -
    /// how big a jump depends on how hard those top-of-range reps felt.
    /// Falls back to plain double progression when RPE wasn't logged
    /// (older sets, or a user who skips the RPE field).
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

        let rpeValues = previousSets.compactMap(\.rpe)
        // Only trust RPE for this suggestion if most of last session's sets
        // actually have it logged - a couple of stray values isn't enough
        // to autoregulate off of.
        let hasReliableRPE = rpeValues.count * 2 >= previousSets.count
        let avgRPE = rpeValues.isEmpty ? nil : rpeValues.reduce(0, +) / Double(rpeValues.count)

        if allHitTop {
            var increment = target.weightIncrementKg
            var rpeNote = ""
            if hasReliableRPE, let avgRPE {
                if avgRPE <= 7 {
                    increment *= 2
                    rpeNote = " Those felt easy (RPE \(formatted(avgRPE))) - jumping up more than usual."
                } else if avgRPE >= 9 {
                    rpeNote = " That was near-max effort (RPE \(formatted(avgRPE))) - keeping the jump small."
                }
            }
            return ProgressionSuggestion(
                suggestedWeightKg: lastWeight + increment,
                targetReps: target.repRangeLow,
                note: "Hit \(target.repRangeHigh) reps on every set last time - go up in weight.\(rpeNote)"
            )
        } else {
            if hasReliableRPE, let avgRPE, avgRPE >= 9.5 {
                return ProgressionSuggestion(
                    suggestedWeightKg: lastWeight,
                    targetReps: previousSets.map(\.reps).min() ?? target.repRangeLow,
                    note: "That was maxed out (RPE \(formatted(avgRPE))) without hitting \(target.repRangeHigh) reps - same weight, focus on form and recovery."
                )
            }
            return ProgressionSuggestion(
                suggestedWeightKg: lastWeight,
                targetReps: target.repRangeHigh,
                note: "Same weight as last time - push for \(target.repRangeHigh) reps on every set."
            )
        }
    }

    private static func formatted(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
