import Foundation

/// Where today's water should be by now, and how past days compared at the
/// same time of day - plain functions so they can be checked without a UI.
nonisolated enum WaterPace {
    /// Minutes after midnight.
    static func minuteOfDay(_ date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Straight-line pace: nothing at waking up, the full target by the end of
    /// the drinking day (a couple of hours before bed).
    static func expectedMl(atMinute now: Int, wakeMinutes: Int, endMinutes: Int, targetMl: Double) -> Double {
        guard endMinutes > wakeMinutes else { return targetMl }
        let progress = Double(now - wakeMinutes) / Double(endMinutes - wakeMinutes)
        return targetMl * min(max(progress, 0), 1)
    }

    /// Fluid in a day's items logged at or before `minute`.
    static func ml(in items: [(time: Date, ml: Double)], byMinute minute: Int) -> Double {
        items.filter { minuteOfDay($0.time) <= minute }.reduce(0) { $0 + $1.ml }
    }

    /// Whole glasses it takes to close `behindMl`, at least one.
    static func glassesToCatchUp(behindMl: Double, glassMl: Int) -> Int {
        max(1, Int((behindMl / Double(max(glassMl, 1))).rounded(.up)))
    }
}
