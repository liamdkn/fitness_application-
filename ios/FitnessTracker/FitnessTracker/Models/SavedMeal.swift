import Foundation

struct SavedMeal: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
}

struct SavedMealItem: Codable, Identifiable, Hashable {
    let id: UUID
    let savedMealId: UUID
    let foodId: UUID?
    let recipeId: UUID?
    let quantity: Double

    enum CodingKeys: String, CodingKey {
        case id
        case savedMealId = "saved_meal_id"
        case foodId = "food_id"
        case recipeId = "recipe_id"
        case quantity
    }
}
