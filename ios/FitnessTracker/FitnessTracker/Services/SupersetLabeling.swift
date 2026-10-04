import Foundation

enum SupersetLabeling {
    /// Maps each superset group id that has 2+ members to a display label
    /// ("Superset A", "Superset B", ...) in order of first appearance.
    /// Groups left with only one member (e.g. after an unpair) are excluded,
    /// so a lone leftover tag never renders a badge.
    static func labels(for exercises: [RoutineDayExercise]) -> [UUID: String] {
        var counts: [UUID: Int] = [:]
        var order: [UUID] = []
        for exercise in exercises {
            guard let groupId = exercise.supersetGroupId else { continue }
            counts[groupId, default: 0] += 1
            if !order.contains(groupId) {
                order.append(groupId)
            }
        }

        let qualifyingGroups = order.filter { (counts[$0] ?? 0) >= 2 }
        var labels: [UUID: String] = [:]
        for (index, groupId) in qualifyingGroups.enumerated() {
            let letter = letter(at: index)
            labels[groupId] = "Superset \(letter)"
        }
        return labels
    }

    /// A, B, C ... then round again after Z. Safe for any index (a negative
    /// one used to be a crash).
    static func letter(at index: Int) -> Character {
        Character(UnicodeScalar(UInt8(65 + (abs(index) % 26))))
    }
}
