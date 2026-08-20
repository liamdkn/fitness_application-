import Foundation

struct Workout: Codable, Identifiable, Hashable {
    let id: UUID
    let routineDayId: UUID?
    let performedAt: Date
    let startedAt: Date
    let endedAt: Date?
    let name: String?
    let notes: String?
    let rating: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case routineDayId = "routine_day_id"
        case performedAt = "performed_at"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case name, notes, rating
    }

    var duration: TimeInterval? {
        guard let endedAt else { return nil }
        return endedAt.timeIntervalSince(startedAt)
    }
}

struct WorkoutSet: Codable, Identifiable, Hashable {
    let id: UUID
    let workoutId: UUID
    let exerciseId: UUID
    let setIndex: Int
    let reps: Int
    let weightKg: Double
    let rpe: Double?
    let isWarmup: Bool
    let isDropSet: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case workoutId = "workout_id"
        case exerciseId = "exercise_id"
        case setIndex = "set_index"
        case reps
        case weightKg = "weight_kg"
        case rpe
        case isWarmup = "is_warmup"
        case isDropSet = "is_drop_set"
    }
}
