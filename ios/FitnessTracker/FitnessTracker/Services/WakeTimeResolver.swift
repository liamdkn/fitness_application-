import Foundation

/// When you usually wake, worked out from the last two weeks of sleep in
/// Apple Health: the median wake time, so one lie-in doesn't move it. Used to
/// time the morning weigh-in nudge. Nil until there are enough recorded nights.
@MainActor
enum WakeTimeResolver {
    private static var cache: (at: Date, minutes: Int?)?

    /// Minutes after midnight, or nil when Health doesn't have a pattern yet.
    static func typicalWakeMinutes() async -> Int? {
        if let cache, Date().timeIntervalSince(cache.at) < 1800 { return cache.minutes }
        let wakes = (try? await HealthKitManager().fetchWakeMinutes(daysBack: 14)) ?? []
        var result: Int?
        if wakes.count >= 4 {
            let sorted = wakes.sorted()
            let middle = sorted.count / 2
            result = sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
        }
        cache = (Date(), result)
        return result
    }
}
