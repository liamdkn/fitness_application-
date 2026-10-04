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
    /// Other muscles the exercise loads, e.g. triceps for a bench press.
    let secondaryMuscleGroups: [String]
    let equipment: String?
    let isCustom: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, category
        case primaryMuscleGroup = "primary_muscle_group"
        case secondaryMuscleGroups = "secondary_muscle_groups"
        case equipment
        case isCustom = "is_custom"
    }

    /// Every muscle group this exercise works, main one first.
    var allMuscleGroups: [String] {
        (primaryMuscleGroup.map { [$0] } ?? []) + secondaryMuscleGroups
    }

    // Old cached copies of the library predate secondary muscle groups.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        category = try container.decode(String.self, forKey: .category)
        primaryMuscleGroup = try container.decodeIfPresent(String.self, forKey: .primaryMuscleGroup)
        secondaryMuscleGroups = try container.decodeIfPresent([String].self, forKey: .secondaryMuscleGroups) ?? []
        equipment = try container.decodeIfPresent(String.self, forKey: .equipment)
        isCustom = try container.decode(Bool.self, forKey: .isCustom)
    }
}
