import Foundation

/// Aiming for an amount: how close counts as "there", and where a pour stands.
nonisolated enum GoalWeigh {
    enum Status: Equatable {
        case under(remaining: Double)
        case onTarget
        case over(by: Double)
    }

    /// How far from the target still counts as hitting it: 3% of it, never less than 1.
    static func tolerance(for target: Double) -> Double { max(1.0, target * 0.03) }

    static func status(amount: Double, target: Double) -> Status {
        let tolerance = tolerance(for: target)
        if amount < target - tolerance { return .under(remaining: ((target - amount) * 10).rounded() / 10) }
        if amount > target + tolerance { return .over(by: ((amount - target) * 10).rounded() / 10) }
        return .onTarget
    }
}
