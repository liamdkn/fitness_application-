import Foundation

struct BodyWeightLog: Codable, Identifiable {
    let id: UUID
    let loggedAt: Date
    let weightKg: Double
    let source: String

    enum CodingKeys: String, CodingKey {
        case id
        case loggedAt = "logged_at"
        case weightKg = "weight_kg"
        case source
    }
}
