import Foundation

/// Sizes the protein, carb and fat sources of a meal so the meal comes to a
/// set of macro targets - "fit this to 40 g protein, 80 g carbs, 15 g fat".
///
/// Each role is one group of foods scaled together (the chicken, or the rice
/// and the pasta). A protein source also carries some carbs and fat, so the
/// groups are solved together: each pass sets one group's size to close the
/// gap in its own macro given everything else, which settles in a few passes
/// because each source is mostly its own macro.
nonisolated enum MealFitter {
    struct Macros: Equatable {
        var calories = 0.0, protein = 0.0, carbs = 0.0, fat = 0.0

        static func + (a: Macros, b: Macros) -> Macros {
            Macros(calories: a.calories + b.calories, protein: a.protein + b.protein, carbs: a.carbs + b.carbs, fat: a.fat + b.fat)
        }
        static func * (m: Macros, k: Double) -> Macros {
            Macros(calories: m.calories * k, protein: m.protein * k, carbs: m.carbs * k, fat: m.fat * k)
        }
    }

    struct Targets {
        var protein: Double?
        var carbs: Double?
        var fat: Double?
    }

    /// What `scale` of a group adds up to: each entry is a food's macros per serving and the servings.
    struct Line {
        let perServing: Macros
        let servings: Double
        var macros: Macros { perServing * servings }
    }

    /// Scale factors for the protein, carb and fat groups (1 = as saved) that
    /// bring `lines` closest to `targets`. `fixed` is everything that isn't
    /// scaled (the "other" foods).
    static func fit(
        protein: [Line], carbs: [Line], fat: [Line], fixed: [Line], targets: Targets
    ) -> (protein: Double, carbs: Double, fat: Double) {
        func total(_ lines: [Line]) -> Macros { lines.reduce(Macros()) { $0 + $1.macros } }
        let base = (p: total(protein), c: total(carbs), f: total(fat), x: total(fixed))
        var scale = (p: 1.0, c: 1.0, f: 1.0)

        for _ in 0..<40 {
            if let target = targets.protein, base.p.protein > 0.01 {
                let others = base.c.protein * scale.c + base.f.protein * scale.f + base.x.protein
                scale.p = clamp((target - others) / base.p.protein)
            }
            if let target = targets.carbs, base.c.carbs > 0.01 {
                let others = base.p.carbs * scale.p + base.f.carbs * scale.f + base.x.carbs
                scale.c = clamp((target - others) / base.c.carbs)
            }
            if let target = targets.fat, base.f.fat > 0.01 {
                let others = base.p.fat * scale.p + base.c.fat * scale.c + base.x.fat
                scale.f = clamp((target - others) / base.f.fat)
            }
        }
        return (protein: scale.p, carbs: scale.c, fat: scale.f)
    }

    /// A new amount made practical: 5 g/ml steps for measured foods, halves for counted ones.
    static func practical(servings: Double, food: Food) -> Double {
        guard servings > 0, food.servingSize > 0 else { return 0 }
        let unit = food.servingUnit.lowercased()
        if unit == "g" || unit == "ml" {
            let amount = max((servings * food.servingSize / 5).rounded() * 5, 5)
            return amount / food.servingSize
        }
        return max((servings * 2).rounded() / 2, 0.5)
    }

    /// How many servings of `food` carry `grams` of one macro.
    static func servings(of food: Food, matching grams: Double, role: FoodCategory) -> Double? {
        let perServing: Double
        switch role {
        case .protein: perServing = food.proteinG
        case .carb: perServing = food.carbsG
        case .fat: perServing = food.fatG
        case .other: return nil
        }
        guard perServing > 0.1, grams > 0 else { return nil }
        return grams / perServing
    }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 6) }
}
