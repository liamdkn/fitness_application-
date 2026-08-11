import Foundation

struct ExerciseProgressionPoint: Codable, Identifiable {
    let workoutId: UUID
    let performedAt: Date
    let bestEst1RM: Double
    let maxWeightKg: Double
    let totalVolumeKg: Double
    let totalReps: Int

    var id: UUID { workoutId }

    enum CodingKeys: String, CodingKey {
        case workoutId = "workout_id"
        case performedAt = "performed_at"
        case bestEst1RM = "best_est_1rm"
        case maxWeightKg = "max_weight_kg"
        case totalVolumeKg = "total_volume_kg"
        case totalReps = "total_reps"
    }
}
