import Foundation

enum SupplementUnit: String, Codable, CaseIterable, Identifiable {
    case serving, scoop, capsule, tablet, softgel, drop, g, mg, ml

    var id: String { rawValue }

    func name(for amount: Double) -> String {
        let one = abs(amount - 1) < 0.001
        switch self {
        case .g, .mg, .ml: return rawValue
        case .serving: return one ? "serving" : "servings"
        case .scoop: return one ? "scoop" : "scoops"
        case .capsule: return one ? "capsule" : "capsules"
        case .tablet: return one ? "tablet" : "tablets"
        case .softgel: return one ? "softgel" : "softgels"
        case .drop: return one ? "drop" : "drops"
        }
    }

    var displayName: String { name(for: 2).capitalized }
}

struct Supplement: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var unit: SupplementUnit
    /// How much of `unit` one serving is (1 scoop, 2 capsules).
    var amountPerServing: Double
    /// Grams in a scoop, so the goal can read in grams.
    var scoopSizeG: Double?
    /// How many times a day it's taken - the "y" in "1 of 2".
    var servingsPerDay: Int
    /// Reminder times, minutes after midnight. Empty = no reminders.
    var reminderTimes: [Int]
    var isActive: Bool
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, name, unit
        case amountPerServing = "amount_per_serving"
        case scoopSizeG = "scoop_size_g"
        case servingsPerDay = "servings_per_day"
        case reminderTimes = "reminder_times"
        case isActive = "is_active"
        case sortOrder = "sort_order"
    }

    /// "1 scoop", "2 capsules", "5 g".
    func amountText(_ amount: Double? = nil) -> String {
        let value = amount ?? amountPerServing
        return "\(AmountLabel.trimmed(value)) \(unit.name(for: value))"
    }
}

struct SupplementOverride: Codable, Identifiable, Hashable {
    let id: UUID
    let supplementId: UUID
    let date: String
    let servingsPerDay: Int?
    let amountPerServing: Double?

    enum CodingKeys: String, CodingKey {
        case id, date
        case supplementId = "supplement_id"
        case servingsPerDay = "servings_per_day"
        case amountPerServing = "amount_per_serving"
    }
}

struct SupplementLog: Codable, Identifiable, Hashable {
    let id: UUID
    let supplementId: UUID
    let date: String
    let amount: Double
    let takenAt: Date

    enum CodingKeys: String, CodingKey {
        case id, date, amount
        case supplementId = "supplement_id"
        case takenAt = "taken_at"
    }
}

/// One supplement on one day: what's planned (after any override for that
/// day) against what's been taken.
struct SupplementDay: Identifiable {
    let supplement: Supplement
    let override: SupplementOverride?
    let logs: [SupplementLog]

    var id: UUID { supplement.id }
    var servingsGoal: Int { override?.servingsPerDay ?? supplement.servingsPerDay }
    var amountPerServing: Double { override?.amountPerServing ?? supplement.amountPerServing }
    var taken: Int { logs.count }
    var isDone: Bool { taken >= servingsGoal }
    var isOverridden: Bool { override != nil }
    var amountTaken: Double { logs.reduce(0) { $0 + $1.amount } }
    var amountGoal: Double { Double(servingsGoal) * amountPerServing }

    /// The day's goal in grams, when it can be told: a scoop of known weight,
    /// or a supplement measured in grams already.
    var goalGrams: Double? {
        switch supplement.unit {
        case .g: return amountGoal
        case .mg: return amountGoal / 1000
        case .scoop: return supplement.scoopSizeG.map { amountGoal * $0 }
        default: return nil
        }
    }

    var takenGrams: Double? {
        switch supplement.unit {
        case .g: return amountTaken
        case .mg: return amountTaken / 1000
        case .scoop: return supplement.scoopSizeG.map { amountTaken * $0 }
        default: return nil
        }
    }
}
