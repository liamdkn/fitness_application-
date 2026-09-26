import Foundation

/// A "banked" treat - a future meal that's going to need more than a
/// normal day's share, paid for by trimming the other days in the same
/// week. Only the plan itself is stored; `CalorieBankCalculator` derives
/// each day's adjusted target from the full set of a week's treats, so
/// moving/deleting one, or a goal's targets changing, never leaves a
/// stale redistribution lying around.
struct PlannedTreat: Codable, Identifiable, Hashable {
    let id: UUID
    let date: String
    let mealSlotId: UUID?
    let label: String
    let extraCalories: Double
    let extraProteinG: Double
    let extraCarbsG: Double
    let extraFatG: Double

    enum CodingKeys: String, CodingKey {
        case id, date, label
        case mealSlotId = "meal_slot_id"
        case extraCalories = "extra_calories"
        case extraProteinG = "extra_protein_g"
        case extraCarbsG = "extra_carbs_g"
        case extraFatG = "extra_fat_g"
    }
}
