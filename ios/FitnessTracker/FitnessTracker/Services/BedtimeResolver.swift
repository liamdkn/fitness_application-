import Foundation

/// Which bedtime the caffeine advice and reminders use: your real one, worked
/// out from when you fell asleep over the last two weeks in Apple Health
/// (Apple doesn't let apps read the Sleep Schedule you set in the Health or
/// Clock app, so the sleep you actually got is the signal available), or the
/// fixed time from settings when that's switched off or there aren't enough
/// recorded nights yet.
@MainActor
enum BedtimeResolver {
    struct Resolved {
        /// Minutes after midnight.
        let minutes: Int
        let fromHealth: Bool
        /// Nights it was worked out from (0 when it's the fixed time).
        let nights: Int
    }

    /// A Health query per screen would be wasteful for a number that moves
    /// slowly, so the answer is reused for half an hour.
    private static var cache: (at: Date, fixed: Int, resolved: Resolved)?
    private static let lookbackDays = 14

    static func resolve(_ preferences: UserPreferences?) async -> Resolved {
        let fixed = preferences?.bedtimeMinutes ?? 1350
        guard preferences?.bedtimeFromHealth ?? true else {
            return Resolved(minutes: fixed, fromHealth: false, nights: 0)
        }
        if let cache, cache.fixed == fixed, Date().timeIntervalSince(cache.at) < 1800 {
            return cache.resolved
        }
        let onsets = (try? await HealthKitManager().fetchSleepOnsets(daysBack: lookbackDays)) ?? []
        let resolved: Resolved
        if let typical = BedtimeEstimate.typicalBedtime(nightMinutes: onsets) {
            resolved = Resolved(minutes: typical, fromHealth: true, nights: onsets.count)
        } else {
            resolved = Resolved(minutes: fixed, fromHealth: false, nights: onsets.count)
        }
        cache = (Date(), fixed, resolved)
        return resolved
    }

    /// Forget the cached answer - after the settings change.
    static func invalidate() { cache = nil }
}
