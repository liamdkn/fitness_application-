import Foundation

struct MealSlot: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case sortOrder = "sort_order"
    }
}
