import Foundation

struct Injury: Codable, Identifiable, Hashable {
    let id: UUID
    let muscleGroup: String
    let notes: String?
    let startedAt: String
    let resolvedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case muscleGroup = "muscle_group"
        case notes
        case startedAt = "started_at"
        case resolvedAt = "resolved_at"
    }

    var isActive: Bool { resolvedAt == nil }
}
