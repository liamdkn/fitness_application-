import Foundation

/// A note tied to one exercise within one specific workout (e.g. "shoulder
/// very sore on this one") - distinct from `Workout.notes` (whole-workout).
struct ExerciseNote: Codable, Identifiable {
    let id: UUID
    let workoutId: UUID
    let exerciseId: UUID
    let note: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case workoutId = "workout_id"
        case exerciseId = "exercise_id"
        case note
        case createdAt = "created_at"
    }
}
