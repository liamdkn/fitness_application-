import Foundation

enum GoalPhaseType: String, Codable, CaseIterable, Identifiable {
    case cut, maintain, bulk

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cut: "Cut"
        case .maintain: "Maintain"
        case .bulk: "Bulk"
        }
    }
}

struct UserGoal: Identifiable {
    let id: UUID
    let effectiveFrom: String
    let phaseType: GoalPhaseType
    let startingWeightKg: Double?
    let durationWeeks: Int
    let dailyCalorieTarget: Double
    let proteinGTarget: Double
    let carbsGTarget: Double?
    let fatGTarget: Double?
    let targetWeightKg: Double?
    let weeklyWeightChangeKg: Double?
    let stepTarget: Int?
    let sleepTargetMinutes: Int?
    let cardioSessionsPerWeek: Int?
    let cardioMinutesPerSession: Int?
}
