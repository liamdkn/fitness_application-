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
    /// A bonus/optional session (e.g. an optional "Day 5") rather than a
    /// required one - the weekly adherence score won't count missing it
    /// against you.
    let isOptional: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case routineId = "routine_id"
        case position, label
        case isOptional = "is_optional"
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
    let supersetGroupId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case routineDayId = "routine_day_id"
        case exerciseId = "exercise_id"
        case position
        case targetSets = "target_sets"
        case repRangeLow = "rep_range_low"
        case repRangeHigh = "rep_range_high"
        case weightIncrementKg = "weight_increment_kg"
        case supersetGroupId = "superset_group_id"
    }
}
