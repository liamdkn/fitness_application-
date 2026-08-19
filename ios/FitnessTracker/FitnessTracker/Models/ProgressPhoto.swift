import Foundation

struct ProgressPhoto: Codable, Identifiable {
    let id: UUID
    let takenAt: String
    let storagePath: String

    enum CodingKeys: String, CodingKey {
        case id
        case takenAt = "taken_at"
        case storagePath = "storage_path"
    }
}
