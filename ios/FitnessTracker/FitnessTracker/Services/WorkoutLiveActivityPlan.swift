import Foundation

/// Which exercise the Live Activity should show, and where you are in it -
/// a plain function so the "what's next" rules can be checked on their own.
nonisolated enum WorkoutLiveActivityPlan {
    struct Entry {
        let name: String
        /// Working sets logged so far (drop sets are extras, not counted).
        let loggedSets: Int
        /// Working-set rows still waiting to be logged.
        let pendingSets: Int
        /// Text for the most recent set logged, if any.
        let lastSet: String?

        var isDone: Bool { pendingSets == 0 }
    }

    /// The exercise you're on is the one you last logged a set for, until its
    /// planned sets are done; then the next unfinished one after it (wrapping
    /// to the earliest unfinished if you've jumped around); before anything
    /// is logged, the first one. `nil` once everything is done.
    static func currentIndex(entries: [Entry], lastLoggedIndex: Int?) -> Int? {
        if let lastLoggedIndex, entries.indices.contains(lastLoggedIndex), !entries[lastLoggedIndex].isDone {
            return lastLoggedIndex
        }
        let start = (lastLoggedIndex ?? -1) + 1
        if let next = entries.indices.dropFirst(start).first(where: { !entries[$0].isDone }) { return next }
        return entries.indices.first { !entries[$0].isDone }
    }

    static func state(
        entries: [Entry], lastLoggedIndex: Int?, restEndsAt: Date?, now: Date = Date()
    ) -> WorkoutActivityAttributes.ContentState {
        let setsLogged = entries.reduce(0) { $0 + $1.loggedSets }
        let lastSet = lastLoggedIndex.flatMap { entries.indices.contains($0) ? entries[$0].lastSet : nil }
        let rest = restEndsAt.flatMap { $0 > now ? $0 : nil }

        guard let index = currentIndex(entries: entries, lastLoggedIndex: lastLoggedIndex) else {
            return .init(
                exerciseName: entries.isEmpty ? "No exercises yet" : "All sets done",
                setNumber: nil, setTotal: nil, lastSet: lastSet, restEndsAt: rest,
                setsLogged: setsLogged, allDone: !entries.isEmpty
            )
        }
        let entry = entries[index]
        return .init(
            exerciseName: entry.name,
            setNumber: entry.loggedSets + 1,
            setTotal: entry.loggedSets + entry.pendingSets,
            lastSet: lastSet, restEndsAt: rest,
            setsLogged: setsLogged, allDone: false
        )
    }

    /// "80 kg x 8" - whole kilos without a decimal point.
    static func setText(name: String, weightKg: Double, reps: Int) -> String {
        let weight = weightKg == weightKg.rounded() ? String(Int(weightKg)) : String(format: "%.1f", weightKg)
        return "\(name) \u{00b7} \(weight) kg x \(reps)"
    }
}
