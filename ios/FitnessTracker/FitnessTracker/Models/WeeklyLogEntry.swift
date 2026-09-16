import Foundation

/// One row of the `weekly_log_summary` RPC - a week's worth of averages,
/// already computed server-side rather than assembled client-side one
/// `WeeklyInsightsViewModel.load()` call per row.
struct WeeklyLogEntry: Decodable, Identifiable {
    /// "yyyy-MM-dd", same plain-date-as-String convention as `NutritionLog`/
    /// `DailyCheckin` - parse with `DateFormatting.date(fromISODate:)`.
    let weekStart: String
    let avgWeightKg: Double?
    /// Half the week's min-to-max weigh-in range - "80.4 +/- 0.3 kg" shows
    /// how much the number actually moved that week, not just the average.
    let weightSpreadKg: Double?
    let avgCalories: Double?
    let avgProteinG: Double?
    let avgCarbsG: Double?
    let avgFatG: Double?
    let avgSteps: Double?

    var id: String { weekStart }

    var weekStartDate: Date {
        DateFormatting.date(fromISODate: weekStart) ?? Date()
    }

    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start"
        case avgWeightKg = "avg_weight_kg"
        case weightSpreadKg = "weight_spread_kg"
        case avgCalories = "avg_calories"
        case avgProteinG = "avg_protein_g"
        case avgCarbsG = "avg_carbs_g"
        case avgFatG = "avg_fat_g"
        case avgSteps = "avg_steps"
    }
}
