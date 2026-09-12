import Foundation

/// Macro totals are cached here (computed client-side from
/// `RecipeIngredient`s at save time), not derived live on every read - see
/// `RecipeRepository.create`/`recompute`.
struct Recipe: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let servingSize: Double
    let servingUnit: String
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let fiberG: Double

    enum CodingKeys: String, CodingKey {
        case id, name
        case servingSize = "serving_size"
        case servingUnit = "serving_unit"
        case calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
    }

    func calories(at quantity: Double) -> Double { calories * quantity }
    func proteinG(at quantity: Double) -> Double { proteinG * quantity }
    func carbsG(at quantity: Double) -> Double { carbsG * quantity }
    func fatG(at quantity: Double) -> Double { fatG * quantity }
    func fiberG(at quantity: Double) -> Double { fiberG * quantity }
}

struct RecipeIngredient: Codable, Identifiable, Hashable {
    let id: UUID
    let recipeId: UUID
    let foodId: UUID
    let quantity: Double

    enum CodingKeys: String, CodingKey {
        case id
        case recipeId = "recipe_id"
        case foodId = "food_id"
        case quantity
    }
}
