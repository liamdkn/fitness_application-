import Foundation

/// Redistributes each planned treat's extra macros across the other days
/// in its week, so the treat's own day gets a raised target (it's going
/// to need it) while the rest of that week gets trimmed by exactly enough
/// to keep the week's total macro budget unchanged - "banking" calories
/// ahead of a treat, rather than just going over on the day and hoping it
/// averages out.
enum CalorieBankCalculator {
    struct DailyAdjustment {
        /// Positive on a treat's own day (target raised); negative on a
        /// day helping fund someone else's treat (target trimmed); zero
        /// on a day with no treats anywhere in its week.
        let calorieDelta: Double
        let proteinDelta: Double
        let carbsDelta: Double
        let fatDelta: Double
        /// Treats whose own day this is - a day can host more than one.
        let treatsToday: [PlannedTreat]
        /// Treats elsewhere in the week this day is helping fund, for a
        /// "saving toward Cinnabon on Sat" style caption.
        let fundedTreats: [PlannedTreat]

        static let none = DailyAdjustment(calorieDelta: 0, proteinDelta: 0, carbsDelta: 0, fatDelta: 0, treatsToday: [], fundedTreats: [])
    }

    /// `weekDates` is whatever the caller considers "the week" (`MealLogHomeView`
    /// already builds a Monday-first one for its strip; reusing it here
    /// keeps the redistribution matching whatever week the UI shows) and
    /// `treats` is every planned treat whose `date` falls somewhere in it.
    static func adjustment(for day: Date, weekDates: [Date], treats: [PlannedTreat]) -> DailyAdjustment {
        guard !treats.isEmpty else { return .none }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)

        func dateOf(_ treat: PlannedTreat) -> Date? {
            DateFormatting.date(fromISODate: treat.date).map { calendar.startOfDay(for: $0) }
        }
        let treatDatesById = Dictionary(uniqueKeysWithValues: treats.compactMap { treat in dateOf(treat).map { (treat.id, $0) } })

        var calorieDelta = 0.0
        var proteinDelta = 0.0
        var carbsDelta = 0.0
        var fatDelta = 0.0
        var treatsToday: [PlannedTreat] = []
        var fundedTreats: [PlannedTreat] = []

        for treat in treats {
            guard let treatDay = treatDatesById[treat.id] else { continue }

            if calendar.isDate(treatDay, inSameDayAs: dayStart) {
                calorieDelta += treat.extraCalories
                proteinDelta += treat.extraProteinG
                carbsDelta += treat.extraCarbsG
                fatDelta += treat.extraFatG
                treatsToday.append(treat)
                continue
            }

            // Spread this treat's surplus across every OTHER day in its
            // week that isn't itself hosting a treat - two treats in the
            // same week each fund themselves from the plain days, rather
            // than compounding off each other's already-raised day.
            let spreadDays = weekDates
                .map { calendar.startOfDay(for: $0) }
                .filter { candidate in
                    guard !calendar.isDate(candidate, inSameDayAs: treatDay) else { return false }
                    return !treats.contains { treatDatesById[$0.id].map { calendar.isDate($0, inSameDayAs: candidate) } ?? false }
                }
            guard !spreadDays.isEmpty, spreadDays.contains(where: { calendar.isDate($0, inSameDayAs: dayStart) }) else { continue }

            let share = Double(spreadDays.count)
            calorieDelta -= treat.extraCalories / share
            proteinDelta -= treat.extraProteinG / share
            carbsDelta -= treat.extraCarbsG / share
            fatDelta -= treat.extraFatG / share
            fundedTreats.append(treat)
        }

        return DailyAdjustment(
            calorieDelta: calorieDelta,
            proteinDelta: proteinDelta,
            carbsDelta: carbsDelta,
            fatDelta: fatDelta,
            treatsToday: treatsToday,
            fundedTreats: fundedTreats
        )
    }
}
