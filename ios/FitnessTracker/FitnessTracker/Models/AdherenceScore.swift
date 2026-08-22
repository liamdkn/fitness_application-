import Foundation

enum AdherenceComponent: String, CaseIterable, Identifiable {
    case calories, protein, steps, training

    var id: String { rawValue }

    var label: String {
        switch self {
        case .calories: "Calories"
        case .protein: "Protein"
        case .steps: "Steps"
        case .training: "Training"
        }
    }
}

/// One component's contribution to a day's adherence score. `score` is nil
/// when there isn't enough data to judge it (nothing logged yet) or when it
/// genuinely doesn't apply that day (training on a planned rest day) -
/// either way it's left out of the overall average rather than counted
/// against you.
struct AdherenceComponentScore: Identifiable {
    let component: AdherenceComponent
    var id: AdherenceComponent { component }
    let score: Double?
    let detail: String
}

struct DailyAdherenceScore {
    let date: Date
    let components: [AdherenceComponentScore]

    /// Plain average of whichever components have a score. Renormalizing
    /// over just the scored components (rather than treating a missing one
    /// as zero) means a rest day, or a day you haven't finished logging
    /// yet, doesn't tank the score for reasons outside your control.
    var overall: Double? {
        let scored = components.compactMap(\.score)
        guard !scored.isEmpty else { return nil }
        return scored.reduce(0, +) / Double(scored.count)
    }
}

/// A week's adherence, built from that week's seven `DailyAdherenceScore`s
/// (shown day-by-day) plus its own component breakdown. Calories/protein/
/// steps are the average of each day's score for that component; training
/// is scored separately against the phase's required-sessions-per-week
/// (when set) rather than averaged from the days, since averaging the
/// per-day hit/miss/rest-day scores would let a string of un-checked-in
/// days quietly count as "not applicable" instead of a missed session.
struct WeeklyAdherenceScore {
    let dailyScores: [DailyAdherenceScore]
    let components: [AdherenceComponentScore]

    var overall: Double? {
        let scored = components.compactMap(\.score)
        guard !scored.isEmpty else { return nil }
        return scored.reduce(0, +) / Double(scored.count)
    }
}
