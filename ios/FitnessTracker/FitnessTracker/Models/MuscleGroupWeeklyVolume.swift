import Foundation

struct MuscleGroupWeeklyVolume: Codable, Identifiable {
    let weekStart: String
    let muscleGroup: String
    let totalVolumeKg: Double
    let totalReps: Int
    let setCount: Int

    var id: String { "\(weekStart)-\(muscleGroup)" }

    enum CodingKeys: String, CodingKey {
        case weekStart = "week_start"
        case muscleGroup = "muscle_group"
        case totalVolumeKg = "total_volume_kg"
        case totalReps = "total_reps"
        case setCount = "set_count"
    }
}
