import Foundation

/// A single day's noise-filtered "trend weight" - see `TrendWeightCalculator.compute`.
struct TrendWeightPoint: Identifiable {
    let date: Date
    let weightKg: Double
    var id: Date { date }
}

/// Smooths noisy day-to-day scale weight into a trend line via EWMA
/// (Hacker's-Diet-style trend weight), so a chart can show "the number
/// that's actually moving" alongside the raw scale readings. Extracted from
/// `AdaptiveTDEEEngine`, which uses the same technique internally to
/// estimate TDEE - this makes the trend line itself available to any view
/// that just wants to plot it (e.g. the Dashboard's weight chart), not just
/// to the TDEE calculation that originally needed it.
enum TrendWeightCalculator {
    /// Same base smoothing rate `AdaptiveTDEEEngine` uses, scaled up for
    /// gaps between weigh-ins so a week without one doesn't mute the next
    /// reading.
    private static let baseAlpha = 0.1

    private struct DailyWeight {
        let date: Date
        let weightKg: Double
    }

    /// One point per day that has an actual weigh-in (same-day logs
    /// averaged together first), each carrying the running EWMA trend
    /// value through that day - so the returned series has one trend value
    /// per raw data point rather than a value for every calendar day.
    static func compute(from logs: [BodyWeightLog]) -> [TrendWeightPoint] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: logs) { calendar.startOfDay(for: $0.loggedAt) }
        let dailyAverages = grouped.map { day, logsForDay in
            DailyWeight(date: day, weightKg: logsForDay.reduce(0) { $0 + $1.weightKg } / Double(logsForDay.count))
        }.sorted { $0.date < $1.date }

        guard let first = dailyAverages.first else { return [] }

        var trend = first.weightKg
        var previousDate = first.date
        var points: [TrendWeightPoint] = [TrendWeightPoint(date: first.date, weightKg: trend)]

        for point in dailyAverages.dropFirst() {
            let gapDays = max(calendar.dateComponents([.day], from: previousDate, to: point.date).day ?? 1, 1)
            let alpha = 1 - pow(1 - baseAlpha, Double(gapDays))
            trend += alpha * (point.weightKg - trend)
            previousDate = point.date
            points.append(TrendWeightPoint(date: point.date, weightKg: trend))
        }

        return points
    }
}
