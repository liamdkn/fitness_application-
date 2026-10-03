import Foundation

/// One cooked batch, split into `portions`. Owns its own `Recipe` (see
/// `recipeId`) holding the per-portion macros - a prep is a snapshot of
/// that day's ingredients/brands, never a template that later batches
/// edit. How much has been eaten is derived from `meal_entries`, not
/// stored here - see `MealPrepCalculator`.
struct MealPrep: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let recipeId: UUID
    let preppedOn: String
    let portions: Double
    let eatWithinDays: Int
    let totalWeightG: Double?
    let finishedAt: Date?
    let location: StorageLocation
    let frozenOn: String?
    let thawedOn: String?

    enum StorageLocation: String, Codable {
        case fridge, freezer
    }

    enum CodingKeys: String, CodingKey {
        case id, name, portions, location
        case recipeId = "recipe_id"
        case preppedOn = "prepped_on"
        case eatWithinDays = "eat_within_days"
        case totalWeightG = "total_weight_g"
        case finishedAt = "finished_at"
        case frozenOn = "frozen_on"
        case thawedOn = "thawed_on"
    }

    var preppedDate: Date { DateFormatting.date(fromISODate: preppedOn) ?? Date() }

    var isFrozen: Bool { location == .freezer }

    var frozenDate: Date? { frozenOn.flatMap(DateFormatting.date(fromISODate:)) }

    /// Last day the batch is meant to be eaten by. Counted from the day it
    /// was cooked, or from the day it last came out of the freezer - thawing
    /// restarts the clock. Not meaningful while `isFrozen`.
    var eatBy: Date {
        let start = thawedOn.flatMap(DateFormatting.date(fromISODate:)) ?? preppedDate
        return Calendar.current.date(byAdding: .day, value: eatWithinDays, to: start) ?? start
    }

    /// Weight of one portion, if the batch's final weight was recorded.
    var portionWeightG: Double? {
        totalWeightG.map { $0 / portions }
    }
}

/// A prep joined with its per-portion recipe and how much of it has been
/// logged - what the list/picker/detail screens actually render.
struct MealPrepSummary: Identifiable, Hashable {
    let prep: MealPrep
    let recipe: Recipe
    let eatenPortions: Double

    var id: UUID { prep.id }
    var remainingPortions: Double { MealPrepCalculator.remaining(portions: prep.portions, eaten: eatenPortions) }
    var isFinished: Bool { prep.finishedAt != nil || remainingPortions <= 0 }
}

/// Pure maths for a prep, kept apart from the repository/views.
enum MealPrepCalculator {
    /// Batch totals split evenly across `portions`.
    static func perPortion(_ totals: DayMacroTotals, portions: Double) -> DayMacroTotals {
        guard portions > 0 else { return DayMacroTotals() }
        return DayMacroTotals(
            calories: totals.calories / portions,
            proteinG: totals.proteinG / portions,
            carbsG: totals.carbsG / portions,
            fatG: totals.fatG / portions,
            fiberG: totals.fiberG / portions
        )
    }

    /// Never negative - logging more than was made just reads as "none left".
    static func remaining(portions: Double, eaten: Double) -> Double {
        max(portions - eaten, 0)
    }

    /// Portions' worth of a served weight, e.g. 420g of a 350g portion = 1.2.
    static func portions(forServedGrams grams: Double, portionWeightG: Double) -> Double? {
        portionWeightG > 0 ? grams / portionWeightG : nil
    }

    /// Shown as "3" or "2.5" - portions are usually whole but can be fractional.
    static func label(_ portions: Double) -> String {
        portions == portions.rounded() ? "\(Int(portions))" : String(format: "%.1f", portions)
    }
}
