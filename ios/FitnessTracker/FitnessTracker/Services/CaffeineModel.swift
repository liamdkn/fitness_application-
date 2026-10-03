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

/// Working a bedtime out from real sleep: the time you actually fell asleep
/// on recent nights, reduced to one typical time. Times are kept on a
/// "night" scale so a bedtime either side of midnight averages sensibly -
/// 23:30 and 00:30 are an hour apart (1410 and 1470), not 23 hours.
nonisolated enum BedtimeEstimate {
    /// Minutes on the night scale for a fall-asleep time: anything before
    /// midday counts as the small hours of the night (+24h), so it sorts
    /// after the evening ones.
    static func nightMinutes(for onset: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: onset)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return minutes < 12 * 60 ? minutes + 1440 : minutes
    }

    /// The median of the nights, as minutes after midnight (0...1439) - the
    /// median rather than the mean so one very late night doesn't drag it.
    /// `nil` with fewer than `minimumNights`, when there isn't a pattern yet.
    static func typicalBedtime(nightMinutes: [Int], minimumNights: Int = 4) -> Int? {
        guard nightMinutes.count >= minimumNights else { return nil }
        let sorted = nightMinutes.sorted()
        let middle = sorted.count / 2
        let median = sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
        return median % 1440
    }
}

/// What to remind about, and when - kept as a plain function so the wording
/// and timing can be checked without a notification centre.
nonisolated enum CaffeineReminderPlan {
    enum Kind: String {
        case cutoff = "caffeine-cutoff"
        case windDown = "caffeine-wind-down"
    }

    struct Reminder {
        let kind: Kind
        let fireDate: Date
        let title: String
        let body: String
    }

    /// Today's reminders given what's been logged so far:
    /// - **cut-off**, half an hour before the latest time a typical cup still
    ///   leaves you under the bedtime target (skipped if that's already past,
    ///   or if no cup would be a problem anyway);
    /// - **wind-down**, an hour before bed, saying how much caffeine is
    ///   projected to be left.
    static func reminders(
        doses: [CaffeineModel.Dose],
        typicalDoseMg: Double,
        bedtime: Date,
        targetMg: Double,
        halfLifeHours: Double,
        now: Date
    ) -> [Reminder] {
        var result: [Reminder] = []
        let soon = now.addingTimeInterval(60)
        let timeFormat = Date.FormatStyle(date: .omitted, time: .shortened)
        let bedText = bedtime.formatted(timeFormat)

        if let cutoff = CaffeineModel.latestDoseTime(
            doseMg: typicalDoseMg, bedtime: bedtime, targetMg: targetMg, existing: doses, halfLifeHours: halfLifeHours
        ), cutoff < bedtime.addingTimeInterval(-3600) {
            let fire = cutoff.addingTimeInterval(-30 * 60)
            if fire > soon {
                result.append(Reminder(
                    kind: .cutoff,
                    fireDate: fire,
                    title: "Last call for caffeine",
                    body: "A ~\(Int(typicalDoseMg.rounded())) mg cup after \(cutoff.formatted(timeFormat)) would leave more than \(Int(targetMg)) mg in you at bedtime (\(bedText))."
                ))
            }
        }

        let windDownAt = bedtime.addingTimeInterval(-3600)
        if windDownAt > soon {
            let left = Int(CaffeineModel.level(at: bedtime, doses: doses, halfLifeHours: halfLifeHours).rounded())
            let body = Double(left) <= targetMg
                ? "About \(left) mg of caffeine will be left at bedtime (\(bedText)) - you're clear. Time to start winding down."
                : "About \(left) mg of caffeine will still be in you at bedtime (\(bedText)), over your \(Int(targetMg)) mg target, so it may take longer to drop off. Start winding down."
            result.append(Reminder(kind: .windDown, fireDate: windDownAt, title: "Wind down", body: body))
        }
        return result
    }
}
