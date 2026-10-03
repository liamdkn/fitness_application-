import Foundation

/// A user's "these are all the same product" bucket - Greek yoghurt,
/// peanut butter - whose members are the different brands bought over
/// time. Per-user (see migration 0051): the shared `foods` catalog is never
/// touched, only which of its rows this user considers equivalent.
struct FoodGroup: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String

    enum CodingKeys: String, CodingKey {
        case id, name
    }
}

struct FoodGroupMember: Codable, Hashable {
    let groupId: UUID
    let foodId: UUID

    enum CodingKeys: String, CodingKey {
        case groupId = "group_id"
        case foodId = "food_id"
    }
}

/// A group joined with its member foods - what the comparison screens render.
struct FoodGroupSummary: Identifiable, Hashable {
    let group: FoodGroup
    let foods: [Food]

    var id: UUID { group.id }
}

/// One food's macros on a common footing (per 100g/ml) so two brands with
/// different serving sizes - a 150g pot against a 170g one - can be ranked
/// fairly.
struct FoodPer100: Hashable {
    let food: Food
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double

    /// Protein you get per 100 kcal - the "which one's actually better
    /// macros" number: a low-calorie, high-protein yoghurt scores high,
    /// regardless of how big its pot is.
    var proteinPer100Kcal: Double {
        calories > 0 ? proteinG / calories * 100 : 0
    }
}

/// Pure comparison maths over a group's foods, kept apart from the views.
enum FoodComparator {
    /// `nil` unless the food is measured in grams or millilitres - there's
    /// no honest per-100g for "1 bar" or "1 slice" without knowing its weight.
    static func per100(_ food: Food) -> FoodPer100? {
        let unit = food.servingUnit.lowercased()
        guard unit == "g" || unit == "ml", food.servingSize > 0 else { return nil }
        let factor = 100 / food.servingSize
        return FoodPer100(
            food: food,
            calories: food.calories * factor,
            proteinG: food.proteinG * factor,
            carbsG: food.carbsG * factor,
            fatG: food.fatG * factor
        )
    }

    enum Metric: String, CaseIterable, Identifiable {
        case proteinPerKcal = "Protein / 100 kcal"
        case caloriesPer100 = "Calories / 100g"
        case proteinPer100 = "Protein / 100g"

        var id: String { rawValue }

        /// Whether a bigger value is the better one - fewer calories wins,
        /// more protein wins.
        var higherIsBetter: Bool { self != .caloriesPer100 }

        func value(of item: FoodPer100) -> Double {
            switch self {
            case .proteinPerKcal: return item.proteinPer100Kcal
            case .caloriesPer100: return item.calories
            case .proteinPer100: return item.proteinG
            }
        }

        func formatted(_ value: Double) -> String {
            switch self {
            case .proteinPerKcal: return String(format: "%.1fg", value)
            case .caloriesPer100: return "\(Int(value.rounded())) kcal"
            case .proteinPer100: return String(format: "%.1fg", value)
            }
        }
    }

    /// Best first by `metric`; foods that can't be put on a per-100g footing
    /// are dropped rather than ranked on a guess.
    static func ranked(_ foods: [Food], by metric: Metric) -> [FoodPer100] {
        foods.compactMap { per100($0) }.sorted {
            metric.higherIsBetter ? metric.value(of: $0) > metric.value(of: $1) : metric.value(of: $0) < metric.value(of: $1)
        }
    }

    /// "Fage 0% has 2.1g more protein per 100 kcal than Tesco Greek" -
    /// the one-line takeaway under a group's ranking. `nil` with fewer than
    /// two rankable foods, or when the top two are effectively tied.
    static func takeaway(_ ranked: [FoodPer100], metric: Metric) -> String? {
        guard ranked.count >= 2, let best = ranked.first, let worst = ranked.last else { return nil }
        let gap = abs(metric.value(of: best) - metric.value(of: worst))
        guard gap >= 0.05 else { return nil }
        let amount: String
        switch metric {
        case .proteinPerKcal: amount = String(format: "%.1fg more protein per 100 kcal", gap)
        case .caloriesPer100: amount = "\(Int(gap.rounded())) fewer kcal per 100g"
        case .proteinPer100: amount = String(format: "%.1fg more protein per 100g", gap)
        }
        return "\(best.food.displayName) has \(amount) than \(worst.food.displayName)."
    }
}
