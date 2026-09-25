import Foundation

struct Gym: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String

    enum CodingKeys: String, CodingKey {
        case id, name
    }
}
