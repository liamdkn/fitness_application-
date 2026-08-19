import Foundation

enum MuscleGroup: String, CaseIterable, Codable, Identifiable {
    case chest, back, shoulders, biceps, triceps, quads, hamstrings, glutes
    case calves, abs, forearms
    case fullBody = "full_body"
    case cardio, mobility

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fullBody: return "Full Body"
        default: return rawValue.capitalized
        }
    }
}

struct Exercise: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let category: String
    let primaryMuscleGroup: String?
    let equipment: String?
    let isCustom: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, category
        case primaryMuscleGroup = "primary_muscle_group"
        case equipment
        case isCustom = "is_custom"
    }
}
