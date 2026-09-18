import Foundation

/// Which exercises belong to a specific workout instance, and their
/// display/reorder position - persisted so removing an exercise mid-session
/// (or reordering it) survives the workout view being torn down and
/// rebuilt (backgrounding, resuming from the Resume banner, app relaunch).
struct WorkoutExercise: Codable, Identifiable, Hashable {
    let id: UUID
    let workoutId: UUID
    let exerciseId: UUID
    let position: Int

    enum CodingKeys: String, CodingKey {
        case id
        case workoutId = "workout_id"
        case exerciseId = "exercise_id"
        case position
    }
}
