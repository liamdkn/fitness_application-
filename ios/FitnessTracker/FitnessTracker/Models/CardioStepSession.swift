import Foundation

struct CardioStepSession: Codable, Identifiable {
    let id: UUID
    let date: String
    let stepsBefore: Int
    let stepsAfter: Int

    enum CodingKeys: String, CodingKey {
        case id, date
        case stepsBefore = "steps_before"
        case stepsAfter = "steps_after"
    }

    var stepsDelta: Int { stepsAfter - stepsBefore }
}
