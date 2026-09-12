import Foundation

/// Macro totals are cached at save time (summed across every item's
/// underlying food/recipe), same reasoning as `Recipe` - a saved-days
/// picker needs to compare several at a glance without re-joining items
/// every time it's opened.
struct SavedDay: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let fiberG: Double

    enum CodingKeys: String, CodingKey {
        case id, name, calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
    }
}

struct SavedDayItem: Codable, Identifiable, Hashable {
    let id: UUID
    let savedDayId: UUID
    let mealSlotId: UUID
    let foodId: UUID?
    let recipeId: UUID?
    let quantity: Double

    enum CodingKeys: String, CodingKey {
        case id
        case savedDayId = "saved_day_id"
        case mealSlotId = "meal_slot_id"
        case foodId = "food_id"
        case recipeId = "recipe_id"
        case quantity
    }
}
