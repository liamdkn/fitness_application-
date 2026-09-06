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
    /// When this *phase* actually began, independent of `effectiveFrom` -
    /// a mid-phase target adjustment (see `GoalsRepository.saveGoal`)
    /// inserts a new row with a later `effectiveFrom` but the same
    /// `phaseStartedAt` as the phase it's adjusting, so "week X of Y"
    /// tracking survives the adjustment instead of looking like the phase
    /// restarted. Equal to `effectiveFrom` for a genuinely new phase.
    let phaseStartedAt: String
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
    let strengthSessionsPerWeek: Int?
    /// How many of `strengthSessionsPerWeek` are optional/bonus sessions
    /// (e.g. an optional "Day 5") - missing one of these isn't scored as a
    /// training miss. Always <= strengthSessionsPerWeek.
    let strengthOptionalSessions: Int?
}
