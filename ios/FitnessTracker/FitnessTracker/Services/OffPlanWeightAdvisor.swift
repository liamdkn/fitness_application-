import Foundation

/// Connects the daily check-in's self-reported "off plan" flag to the
/// weight chart - a same-day water-weight bump after an off-plan day is
/// the single most common reason someone's scale and trend line suddenly
/// disagree, and it reads as alarming without that context. Both halves
/// here are plain date-joined lookups/averages, not statistical modeling -
/// `evaluateHistory`'s minimum sample size exists specifically because a
/// handful of data points would be actively misleading given how much
/// individual water retention varies.
enum OffPlanWeightAdvisor {
    /// How far above trend counts as a real bump worth commenting on,
    /// rather than ordinary day-to-day scale noise.
    private static let bumpThresholdKg = 0.2
    /// A trend move smaller than this over the off-plan window reads as
    /// "hasn't moved" in the note.
    private static let trendStableThresholdKg = 0.15
    /// An off-plan flag only informs the inline note within this many days
    /// of today - older flags are the historical stat's territory, not a
    /// same-week explanation.
    private static let recentWindowDays = 2
    /// Below this many historical occurrences, an average day-after delta
    /// is too noisy to present as a personal stat rather than coincidence.
    static let minimumHistoricalOccurrences = 15

    struct RecentFlagInsight {
        let deltaKg: Double
        let offPlanDayLabels: [String]
        let trendHasMoved: Bool
    }

    struct HistoricalStat {
        let averageDeltaKg: Double
        let occurrenceCount: Int
    }

    /// How many days after a flagged off-plan day a water-weight bump can
    /// still be showing on the scale - shared default for
    /// `excludingBumpDates`, matching this type's own "typically water
    /// weight, settles in 2-3 days" framing.
    static let defaultBumpSettleDays = 3

    /// `weights` with any reading from a flagged off-plan day's bump
    /// window removed - the day of the check-in that reported it
    /// (`yesterdayOffPlan`, so the morning after the off-plan day itself)
    /// through `settleDays` later. The off-plan day's own weigh-in isn't
    /// excluded - it predates that day's eating.
    ///
    /// This only ever affects a trend/average computed FROM the returned
    /// `filtered` list - it doesn't touch `weights` itself or anything
    /// persisted, so a raw history view/chart should keep using the
    /// unfiltered data and simply not call this. Anywhere that does call
    /// it and gets back `excludedCount > 0` should say so in the UI (see
    /// this file's own doc comment) rather than presenting the result as
    /// if it read straight off the scale.
    static func excludingBumpDates(
        from weights: [BodyWeightLog],
        checkins: [DailyCheckin],
        settleDays: Int = defaultBumpSettleDays
    ) -> (filtered: [BodyWeightLog], excludedCount: Int) {
        let calendar = Calendar.current
        var bumpDates: Set<Date> = []
        for checkin in checkins {
            guard checkin.yesterdayOffPlan == true,
                  let checkinDate = DateFormatting.date(fromISODate: checkin.checkinDate)
            else { continue }
            for offset in 0..<settleDays {
                if let bumpDate = calendar.date(byAdding: .day, value: offset, to: checkinDate) {
                    bumpDates.insert(calendar.startOfDay(for: bumpDate))
                }
            }
        }
        let filtered = weights.filter { !bumpDates.contains(calendar.startOfDay(for: $0.loggedAt)) }
        return (filtered, weights.count - filtered.count)
    }

    /// `weights` is whatever window `TrendWeightCalculator` should warm up
    /// over (recent weigh-ins, most-recent-last is fine, order doesn't
    /// matter - it sorts internally); `recentCheckins` just needs to cover
    /// the last few days.
    static func evaluateRecentFlag(weights: [BodyWeightLog], recentCheckins: [DailyCheckin]) -> RecentFlagInsight? {
        let calendar = Calendar.current
        let trendPoints = TrendWeightCalculator.compute(from: weights)
        guard let latestWeight = weights.max(by: { $0.loggedAt < $1.loggedAt }),
              calendar.isDateInToday(latestWeight.loggedAt),
              let latestTrend = trendPoints.last,
              calendar.isDateInToday(latestTrend.date)
        else { return nil }

        let delta = latestWeight.weightKg - latestTrend.weightKg
        guard delta >= bumpThresholdKg else { return nil }

        let today = Date()
        let offPlanDates: [Date] = recentCheckins.compactMap { checkin in
            guard checkin.yesterdayOffPlan == true,
                  let checkinDate = DateFormatting.date(fromISODate: checkin.checkinDate),
                  let offPlanDate = calendar.date(byAdding: .day, value: -1, to: checkinDate)
            else { return nil }
            let daysAgo = calendar.dateComponents([.day], from: offPlanDate, to: today).day ?? .max
            return daysAgo <= recentWindowDays ? offPlanDate : nil
        }
        guard !offPlanDates.isEmpty else { return nil }

        // Trend value from right before the earliest flagged day, compared
        // to today's - whether the smoothed trend has actually shifted,
        // not just the raw scale reading.
        let earliestFlagged = offPlanDates.min() ?? today
        let trendBefore = trendPoints.last(where: { $0.date < earliestFlagged })?.weightKg ?? latestTrend.weightKg
        let trendHasMoved = abs(latestTrend.weightKg - trendBefore) >= trendStableThresholdKg

        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        let labels = offPlanDates.sorted().map { formatter.string(from: $0) }

        return RecentFlagInsight(deltaKg: delta, offPlanDayLabels: labels, trendHasMoved: trendHasMoved)
    }

    /// `offPlanCheckins` every check-in with `yesterdayOffPlan == true`
    /// (see `DailyCheckinRepository.fetchOffPlanDays`); `weightsByDate`
    /// every available day's weight, start-of-day keyed with same-day logs
    /// pre-averaged, spanning at least the day before the earliest flag
    /// through the day after the latest one.
    static func evaluateHistory(offPlanCheckins: [DailyCheckin], weightsByDate: [Date: Double]) -> HistoricalStat? {
        let calendar = Calendar.current
        var deltas: [Double] = []
        for checkin in offPlanCheckins {
            guard checkin.yesterdayOffPlan == true,
                  let checkinDate = DateFormatting.date(fromISODate: checkin.checkinDate),
                  let offPlanDay = calendar.date(byAdding: .day, value: -1, to: checkinDate),
                  let dayAfter = calendar.date(byAdding: .day, value: 1, to: offPlanDay),
                  let before = weightsByDate[calendar.startOfDay(for: offPlanDay)],
                  let after = weightsByDate[calendar.startOfDay(for: dayAfter)]
            else { continue }
            deltas.append(after - before)
        }
        guard deltas.count >= minimumHistoricalOccurrences else { return nil }
        return HistoricalStat(averageDeltaKg: deltas.reduce(0, +) / Double(deltas.count), occurrenceCount: deltas.count)
    }
}
