import Foundation

/// Sizing food to a carb target - what the preworkout meal uses to say "this
/// much of that gets you there".
nonisolated enum PreworkoutCarbs {
    /// Carbs to eat before training: `gramsPerKg` of the given bodyweight.
    static func targetG(weightKg: Double?, gramsPerKg: Double) -> Double? {
        guard let weightKg, weightKg > 0, gramsPerKg > 0 else { return nil }
        return (weightKg * gramsPerKg).rounded()
    }

    /// Servings of `food` that supply about `carbsG`, rounded to something
    /// weighable: 5 g or ml for measured foods, half a unit for counted ones
    /// (a banana, a rice cake). Nil if the food has no carbs to speak of.
    static func servings(of food: Food, forCarbsG carbsG: Double) -> Double? {
        guard carbsG > 0, food.carbsG > 0.5, food.servingSize > 0 else { return nil }
        let exact = carbsG / food.carbsG
        let unit = food.servingUnit.lowercased()
        if unit == "g" || unit == "ml" {
            let amount = (exact * food.servingSize / 5).rounded() * 5
            return amount > 0 ? amount / food.servingSize : nil
        }
        let halves = (exact * 2).rounded() / 2
        return halves > 0 ? halves : nil
    }
}
