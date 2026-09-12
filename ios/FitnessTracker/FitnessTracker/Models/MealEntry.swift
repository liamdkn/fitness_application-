import Foundation

struct MealEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let date: String
    let mealSlotId: UUID
    let foodId: UUID?
    let recipeId: UUID?
    let quantity: Double
    let loggedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, date
        case mealSlotId = "meal_slot_id"
        case foodId = "food_id"
        case recipeId = "recipe_id"
        case quantity
        case loggedAt = "logged_at"
    }
}
