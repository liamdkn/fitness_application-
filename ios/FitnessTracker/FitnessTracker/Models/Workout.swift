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
    /// Which gym this session happened at, if the user's set one - lets
    /// weight suggestions (`WorkoutRepository.previousSets`) prefer history
    /// from the same gym, since equipment (dumbbell jumps, machine brands)
    /// commonly differs between gyms.
    let gymId: UUID?
    /// Populated only if a same-day Apple Watch "Functional Strength
    /// Training" workout was matched and the user confirmed enriching
    /// this workout with it (see `WatchActivityViewModel`) - never set by
    /// anything logged in-app.
    let avgHeartRate: Int?
    let activeCalories: Double?
    let healthkitWorkoutUUID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case routineDayId = "routine_day_id"
        case performedAt = "performed_at"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case name, notes, rating
        case avgHeartRate = "avg_heart_rate"
        case activeCalories = "active_calories"
        case healthkitWorkoutUUID = "healthkit_workout_uuid"
        case gymId = "gym_id"
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
