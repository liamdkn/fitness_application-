import Foundation

enum AdherenceComponent: String, CaseIterable, Identifiable, Hashable {
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

    /// Relative weight in the overall score when this component has data.
    /// Calories and training are the two levers that most directly decide
    /// whether a cut/bulk actually works, so they carry the most weight;
    /// protein mostly rides along once calories are in check (only a
    /// shortfall costs points at all); steps is the most forgiving
    /// day-to-day lever, hence the lightest weight. These don't need to
    /// sum to 1 - `weightedOverall` renormalizes over whichever components
    /// actually have a score, so a day/week missing some components still
    /// distributes correctly across the ones it has.
    var weight: Double {
        switch self {
        case .calories: 0.35
        case .protein: 0.25
        case .training: 0.25
        case .steps: 0.15
        }
    }
}

/// One component's contribution to a day's adherence score. `score` is nil
/// when there isn't enough data to judge it (nothing logged yet) or when it
/// genuinely doesn't apply that day (training on a planned rest day) -
/// either way it's left out of the overall average rather than counted
/// against you.
struct AdherenceComponentScore: Identifiable, Hashable {
    let component: AdherenceComponent
    var id: AdherenceComponent { component }
    let score: Double?
    let detail: String
}

/// Minimum number of scored components before `overall` is considered
/// meaningful. Below this, a single component (e.g. only steps logged,
/// nothing else) would otherwise stand in for the whole day/week - excluded
/// instead, the same treatment as any other "not enough data" case, so a
/// thinly-logged day/week can't read identically to a fully-tracked one.
private let minScoredComponentsForOverall = 2

extension Array where Element == AdherenceComponentScore {
    var scoredCount: Int { compactMap(\.score).count }

    /// Weighted average of whichever components have a score, renormalized
    /// over just those components' weights - an excluded component neither
    /// counts against you nor skews the blend toward the ones that do
    /// apply. nil below `minScoredComponentsForOverall`.
    var weightedOverall: Double? {
        guard scoredCount >= minScoredComponentsForOverall else { return nil }
        var weightedSum = 0.0
        var totalWeight = 0.0
        for item in self {
            guard let score = item.score else { continue }
            weightedSum += score * item.component.weight
            totalWeight += item.component.weight
        }
        guard totalWeight > 0 else { return nil }
        return weightedSum / totalWeight
    }
}

struct DailyAdherenceScore: Hashable {
    let date: Date
    let components: [AdherenceComponentScore]

    /// How many of `components` had enough data to be scored, out of how
    /// many apply at all - shown alongside `overall` so a viewer can tell a
    /// thinly-logged day from a fully-tracked one even when both happen to
    /// average out to a similar number.
    var scoredCount: Int { components.scoredCount }
    var totalCount: Int { components.count }

    /// Weighted average of whichever components have a score - see
    /// `AdherenceComponent.weight`. nil below `minScoredComponentsForOverall`,
    /// same as a rest day or a day you haven't finished logging yet.
    var overall: Double? { components.weightedOverall }
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

    var scoredCount: Int { components.scoredCount }
    var totalCount: Int { components.count }

    var overall: Double? { components.weightedOverall }
}
