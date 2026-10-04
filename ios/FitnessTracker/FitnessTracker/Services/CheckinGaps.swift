import Foundation

/// Days with no weigh-in and no daily check-in - what the missed-check-in
/// banner, the escalating reminder and Weigh-In History's gap rows are built on.
nonisolated enum CheckinGaps {
    /// Consecutive days, counting back from yesterday, with nothing logged.
    /// Today doesn't count - it isn't over yet.
    static func consecutiveMissed(logged: Set<String>, today: Date, lookback: Int = 30, calendar: Calendar = .current) -> Int {
        var count = 0
        for offset in 1...lookback {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { break }
            if logged.contains(DateFormatting.isoDate(day)) { break }
            count += 1
        }
        return count
    }

    /// A run of days between two weigh-ins with none logged.
    struct Gap: Equatable {
        let firstMissing: Date
        let lastMissing: Date
        var days: Int {
            (Calendar.current.dateComponents([.day], from: firstMissing, to: lastMissing).day ?? 0) + 1
        }
    }

    /// The gap, if any, between two weigh-in days (`earlier` before `later`):
    /// the days strictly between them.
    static func gap(between earlier: Date, and later: Date, calendar: Calendar = .current) -> Gap? {
        let start = calendar.startOfDay(for: earlier)
        let end = calendar.startOfDay(for: later)
        guard let first = calendar.date(byAdding: .day, value: 1, to: start),
              let last = calendar.date(byAdding: .day, value: -1, to: end),
              first <= last else { return nil }
        return Gap(firstMissing: first, lastMissing: last)
    }
}

/// Reads which of the recent days have a weigh-in or check-in.
struct CheckinGapService {
    private let weightRepository = BodyWeightRepository()
    private let checkinRepository = DailyCheckinRepository()

    /// ISO dates in the last `days` days with either kind of entry; nil when
    /// neither could be read (offline) - then nothing is flagged.
    func loggedDates(days: Int = 30) async -> Set<String>? {
        let weights = try? await weightRepository.fetchRecent(days: days)
        let checkins = try? await checkinRepository.fetchRecent(days: days)
        guard weights != nil || checkins != nil else { return nil }
        var dates = Set<String>()
        for log in weights ?? [] { dates.insert(DateFormatting.isoDate(log.loggedAt)) }
        for checkin in checkins ?? [] { dates.insert(checkin.checkinDate) }
        return dates
    }
}
