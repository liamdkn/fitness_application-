import Foundation

/// Estimates how much caffeine is in the body through the day from the
/// doses logged - simple exponential decay with a half-life. It ignores
/// absorption (peak is really 30-60 minutes after drinking) and treats every
/// dose as arriving at once; for "is it still in my system at bedtime" that
/// simplification is on the cautious side. The half-life is the biggest
/// unknown: ~5 hours is the usual adult figure, but it runs from about 3 to 9
/// between people, which is why it's a setting.
nonisolated enum CaffeineModel {
    struct Dose {
        let time: Date
        let mg: Double
    }

    struct Point {
        let time: Date
        let mg: Double
    }

    /// mg still in the body at `moment` - each earlier dose halves every
    /// `halfLifeHours`. Doses after `moment` haven't happened yet.
    static func level(at moment: Date, doses: [Dose], halfLifeHours: Double) -> Double {
        guard halfLifeHours > 0 else { return 0 }
        return doses.reduce(0) { total, dose in
            let hours = moment.timeIntervalSince(dose.time) / 3600
            guard hours >= 0 else { return total }
            return total + dose.mg * pow(0.5, hours / halfLifeHours)
        }
    }

    /// The level sampled every `stepMinutes` from `start` to `end`, plus a
    /// sample just before and at each dose so the curve shows each jump.
    static func curve(doses: [Dose], halfLifeHours: Double, from start: Date, to end: Date, stepMinutes: Int = 10) -> [Point] {
        var times: [Date] = []
        var t = start
        while t <= end {
            times.append(t)
            t = t.addingTimeInterval(Double(stepMinutes) * 60)
        }
        for dose in doses where dose.time >= start && dose.time <= end {
            times.append(dose.time.addingTimeInterval(-1))
            times.append(dose.time)
        }
        return times.sorted().map { Point(time: $0, mg: level(at: $0, doses: doses, halfLifeHours: halfLifeHours)) }
    }

    static func totalMg(_ doses: [Dose]) -> Double {
        doses.reduce(0) { $0 + $1.mg }
    }

    /// The latest time a further `doseMg` can be taken and still be at or
    /// under `targetMg` by `bedtime`, given the doses already taken (and any
    /// logged for later). `nil` when the existing doses alone already leave
    /// more than the target at bedtime - no extra dose is then safe at any time.
    static func latestDoseTime(
        doseMg: Double,
        bedtime: Date,
        targetMg: Double,
        existing: [Dose],
        halfLifeHours: Double
    ) -> Date? {
        guard doseMg > 0, halfLifeHours > 0 else { return nil }
        let room = targetMg - level(at: bedtime, doses: existing, halfLifeHours: halfLifeHours)
        guard room > 0 else { return nil }
        // doseMg * 0.5^(hoursBeforeBed / halfLife) <= room
        if doseMg <= room { return bedtime }
        let hoursBeforeBed = halfLifeHours * log2(doseMg / room)
        return bedtime.addingTimeInterval(-hoursBeforeBed * 3600)
    }

    /// Today's bedtime as a date, from minutes-after-midnight - bedtimes past
    /// midnight count as the following calendar day's early hours, so 00:30
    /// is half an hour after the day's last evening, not before its morning.
    static func bedtime(onDayOf day: Date, minutesAfterMidnight: Int, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        let base = calendar.date(byAdding: .minute, value: minutesAfterMidnight, to: start) ?? start
        // Anything before 04:00 is the small hours of the *next* night.
        return minutesAfterMidnight < 240 ? (calendar.date(byAdding: .day, value: 1, to: base) ?? base) : base
    }
}
