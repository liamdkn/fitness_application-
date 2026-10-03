import Foundation

/// The one place the calories-from-macros maths lives, so every screen that
/// takes calories and macros together asks the same question the same way:
/// do these numbers agree? (Protein and carbs are 4 kcal per gram, fat 9.)
///
/// It is used in two modes. Where the app owns the numbers - a planned treat,
/// a goal - a mismatch is *enforced*: the form won't save until it adds up.
/// Where the numbers are copied off someone else's food label, a mismatch is
/// only a *warning*, because real labels round, count alcohol and sugar
/// alcohols, and treat fibre inconsistently - a correct label can look "off".
nonisolated enum MacroEnergy {
    static let kcalPerGramProtein = 4.0
    static let kcalPerGramCarbs = 4.0
    static let kcalPerGramFat = 9.0
    /// Fibre isn't fully digested - roughly 2 kcal/g where it's counted at all.
    static let kcalPerGramFibre = 2.0

    /// How far calories may sit from what the macros come to before it counts
    /// as a mismatch: the larger of a flat amount and a share of the calories.
    struct Tolerance {
        let minimumKcal: Double
        let fraction: Double

        /// For the app's own numbers (treats): tight, so a forgotten macro shows.
        static let strict = Tolerance(minimumKcal: 10, fraction: 0.04)
        /// For numbers off a food label: loose, since labels round and differ in method.
        static let label = Tolerance(minimumKcal: 5, fraction: 0.10)

        func allowance(for calories: Double) -> Double { max(minimumKcal, calories * fraction) }
    }

    /// Calories these macros come to, ignoring fibre.
    static func kcal(protein: Double, carbs: Double, fat: Double) -> Double {
        protein * kcalPerGramProtein + carbs * kcalPerGramCarbs + fat * kcalPerGramFat
    }

    struct Check {
        /// What was entered.
        let calories: Double
        /// What the macros alone come to.
        let macroKcal: Double
        /// With fibre known, the range the macros can legitimately come to:
        /// carbs may include fibre (counts as 0 kcal, so lower) or exclude it
        /// (counts as ~2 kcal/g, so higher). Equal to `macroKcal` with no fibre.
        let lowKcal: Double
        let highKcal: Double
        let allowance: Double

        var isConsistent: Bool {
            calories >= lowKcal - allowance && calories <= highKcal + allowance
        }

        /// Calories the macros don't account for (negative when the macros
        /// add up to *more* than the calories).
        var unassignedKcal: Double { calories - macroKcal }
    }

    static func check(
        calories: Double,
        protein: Double,
        carbs: Double,
        fat: Double,
        fiber: Double? = nil,
        tolerance: Tolerance = .strict
    ) -> Check {
        let base = kcal(protein: protein, carbs: carbs, fat: fat)
        let fibre = max(fiber ?? 0, 0)
        return Check(
            calories: calories,
            macroKcal: base,
            lowKcal: base - fibre * kcalPerGramCarbs,
            highKcal: base + fibre * kcalPerGramFibre,
            allowance: tolerance.allowance(for: calories)
        )
    }

    /// Carbs and fat grams that would soak up `kcal` left unassigned, split
    /// 60/40 by energy - a neutral default for "I know it's 800 more kcal,
    /// it's mostly cake", which the user can still adjust afterwards.
    static func fillRemainder(kcal: Double) -> (carbsG: Double, fatG: Double) {
        guard kcal > 0 else { return (0, 0) }
        let carbs = (kcal * 0.6 / kcalPerGramCarbs).rounded()
        let fat = (kcal * 0.4 / kcalPerGramFat).rounded()
        return (carbs, fat)
    }
}
