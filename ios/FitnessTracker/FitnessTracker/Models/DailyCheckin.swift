import Foundation

struct DailyCheckin: Codable, Identifiable {
    let id: UUID
    let checkinDate: String
    let weightKg: Double?
    let routineDayId: UUID?
    let workoutChoiceLabel: String?
    let isRestDay: Bool
    let energyLevel: Int?
    let sorenessLevel: Int?
    let yesterdayWaterMl: Int?
    let yesterdayOffPlan: Bool?
    let yesterdayOffPlanNotes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case checkinDate = "checkin_date"
        case weightKg = "weight_kg"
        case routineDayId = "routine_day_id"
        case workoutChoiceLabel = "workout_choice_label"
        case isRestDay = "is_rest_day"
        case energyLevel = "energy_level"
        case sorenessLevel = "soreness_level"
        case yesterdayWaterMl = "yesterday_water_ml"
        case yesterdayOffPlan = "yesterday_off_plan"
        case yesterdayOffPlanNotes = "yesterday_off_plan_notes"
    }
}
