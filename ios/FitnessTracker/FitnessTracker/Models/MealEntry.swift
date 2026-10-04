import Foundation

struct MealEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let date: String
    let mealSlotId: UUID
    let foodId: UUID?
    let recipeId: UUID?
    let quantity: Double
    let loggedAt: Date
    /// When it was actually eaten, if known (see `displayTime`).
    var eatenAt: Date? = nil

    /// The time to show and line up against other data: when it was eaten,
    /// or failing that when it was logged.
    var displayTime: Date { eatenAt ?? loggedAt }

    enum CodingKeys: String, CodingKey {
        case id, date
        case mealSlotId = "meal_slot_id"
        case foodId = "food_id"
        case recipeId = "recipe_id"
        case quantity
        case loggedAt = "logged_at"
        case eatenAt = "eaten_at"
    }
}
