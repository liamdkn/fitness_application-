import Foundation

struct MuscleGroupVolumeFlag {
    let muscleGroup: String
    let currentVolumeKg: Double
    let trailingAverageVolumeKg: Double
}

/// Flags muscle groups whose current week's training volume is well below
/// their OWN recent average - a lightweight stand-in for hand-configured
/// MEV/MAV/MRV volume landmarks, using each muscle group as its own
/// baseline rather than a generic one-size-fits-all number.
enum MuscleGroupVolumeAnalyzer {
    /// Not really "trained volume" in the lifting sense - excluded so a
    /// cardio-heavy week doesn't trigger a false "undertrained" flag there.
    private static let excludedGroups: Set<String> = ["cardio", "mobility"]

    /// How far below its own trailing average a muscle group's current
    /// week has to fall before it's worth flagging.
    private static let underTrainedThreshold = 0.5

    static func evaluate(rows: [MuscleGroupWeeklyVolume]) -> [MuscleGroupVolumeFlag] {
        guard !rows.isEmpty else { return [] }
        let weeks = Set(rows.map(\.weekStart)).sorted()
        // Need at least one full trailing week plus the current one to
        // have a baseline to compare against.
        guard let currentWeek = weeks.last, weeks.count >= 2 else { return [] }
        let trailingWeeks = Set(weeks.dropLast())

        let byGroup = Dictionary(grouping: rows) { $0.muscleGroup }
        var flags: [MuscleGroupVolumeFlag] = []

        for (group, groupRows) in byGroup {
            guard !excludedGroups.contains(group) else { continue }
            let trailingRows = groupRows.filter { trailingWeeks.contains($0.weekStart) }
            guard !trailingRows.isEmpty else { continue }
            // Divide by the total number of trailing weeks in the window,
            // not just the weeks this group has a row for - a week with
            // zero sets for a group has no row at all, and skipping it
            // would silently inflate the average.
            let trailingAverage = trailingRows.reduce(0.0) { $0 + $1.totalVolumeKg } / Double(trailingWeeks.count)
            guard trailingAverage > 0 else { continue }
            let currentVolume = groupRows.first { $0.weekStart == currentWeek }?.totalVolumeKg ?? 0

            if currentVolume < trailingAverage * underTrainedThreshold {
                flags.append(MuscleGroupVolumeFlag(
                    muscleGroup: group,
                    currentVolumeKg: currentVolume,
                    trailingAverageVolumeKg: trailingAverage
                ))
            }
        }

        return flags.sorted { $0.muscleGroup < $1.muscleGroup }
    }
}
