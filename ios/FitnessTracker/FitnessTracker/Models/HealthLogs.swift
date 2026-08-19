import Foundation

struct StepLog: Encodable {
    let userId: UUID
    let date: String
    let stepCount: Int
    let source: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case date
        case stepCount = "step_count"
        case source
    }
}

struct SleepLog: Encodable {
    let userId: UUID
    let date: String
    let totalSleepMinutes: Int
    let inBedMinutes: Int
    let source: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case date
        case totalSleepMinutes = "total_sleep_minutes"
        case inBedMinutes = "in_bed_minutes"
        case source
    }
}

enum DateFormatting {
    static func isoDate(_ date: Date) -> String {
        isoDateFormatter.string(from: date)
    }

    /// Parses a "yyyy-MM-dd" string as produced by `isoDate(_:)` back into
    /// a Date at local midnight. Used when comparing a `date`-column value
    /// (stored as a plain string on the model) against a Date range.
    static func date(fromISODate string: String) -> Date? {
        isoDateFormatter.date(from: string)
    }

    private static let isoDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        return formatter
    }()

    /// The most recent date (<= reference) that falls on `weekday`
    /// (Calendar.weekday numbering: 1=Sunday...7=Saturday). Used to find the
    /// start of the user's configured check-in week, since
    /// Calendar.dateInterval(of: .weekOfYear) doesn't respect a
    /// user-configured week-start day.
    static func startOfCheckinWeek(weekday: Int, reference: Date = Date(), calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: reference)
        let todayWeekday = calendar.component(.weekday, from: today)
        let daysSince = (todayWeekday - weekday + 7) % 7
        return calendar.date(byAdding: .day, value: -daysSince, to: today) ?? today
    }
}
