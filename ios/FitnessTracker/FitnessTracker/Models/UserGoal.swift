import Foundation

struct UserGoal: Identifiable {
    let id: UUID
    let effectiveFrom: String
    let dailyCalorieTarget: Double
    let proteinGTarget: Double
    let carbsGTarget: Double?
    let fatGTarget: Double?
    let targetWeightKg: Double?
    let weeklyWeightChangeKg: Double?
    let stepTarget: Int?
    let sleepTargetMinutes: Int?
}
