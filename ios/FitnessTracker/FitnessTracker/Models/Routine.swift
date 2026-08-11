import Foundation

struct Routine: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id, name
        case isActive = "is_active"
    }
}

struct RoutineDay: Codable, Identifiable, Hashable {
    let id: UUID
    let routineId: UUID
    let position: Int
    let label: String

    enum CodingKeys: String, CodingKey {
        case id
        case routineId = "routine_id"
        case position, label
    }
}

struct RoutineDayExercise: Codable, Identifiable, Hashable {
    let id: UUID
    let routineDayId: UUID
    let exerciseId: UUID
    let position: Int
    let targetSets: Int
    let repRangeLow: Int
    let repRangeHigh: Int
    let weightIncrementKg: Double

    enum CodingKeys: String, CodingKey {
        case id
        case routineDayId = "routine_day_id"
        case exerciseId = "exercise_id"
        case position
        case targetSets = "target_sets"
        case repRangeLow = "rep_range_low"
        case repRangeHigh = "rep_range_high"
        case weightIncrementKg = "weight_increment_kg"
    }
}
