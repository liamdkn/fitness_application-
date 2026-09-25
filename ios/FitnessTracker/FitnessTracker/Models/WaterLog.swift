import Foundation

struct WaterContainer: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let volumeMl: Int

    enum CodingKeys: String, CodingKey {
        case id, name
        case volumeMl = "volume_ml"
    }
}

/// One log entry - `amountMl` is copied from the container's volume at log
/// time (when `containerId` is set), not looked up live, so a later edit to
/// the container's own volume doesn't retroactively change what an already-
/// logged day adds up to.
struct WaterLog: Codable, Identifiable, Hashable {
    let id: UUID
    let date: String
    let amountMl: Int
    let containerId: UUID?
    let loggedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, date
        case amountMl = "amount_ml"
        case containerId = "container_id"
        case loggedAt = "logged_at"
    }
}
