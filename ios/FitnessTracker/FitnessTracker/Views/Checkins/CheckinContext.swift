import Foundation

/// What surrounds a weekly check-in: the phase it fell in, the week's
/// averages, and how it compares with the check-in before it. Built once for
/// the whole history so each row and detail screen is just a lookup.
struct CheckinContext {
    let goals: [UserGoal]          // oldest first
    let weeks: [String: WeeklyLogEntry]  // by Monday date

    /// The phase in force on the check-in's date.
    func goal(for checkin: WeeklyCheckin) -> UserGoal? {
        goals.last { $0.effectiveFrom <= checkin.checkinDate }
    }

    /// "Cut, week 5 of 12".
    func phaseLabel(for checkin: WeeklyCheckin) -> String? {
        guard let goal = goal(for: checkin) else { return nil }
        guard let started = DateFormatting.date(fromISODate: goal.phaseStartedAt),
              let date = DateFormatting.date(fromISODate: checkin.checkinDate) else { return goal.phaseType.displayName }
        let days = Calendar.current.dateComponents([.day], from: started, to: date).day ?? 0
        let week = checkin.weekNumber ?? max(days / 7 + 1, 1)
        return "\(goal.phaseType.displayName), week \(week) of \(goal.durationWeeks)"
    }

    /// The Monday-to-Sunday week the check-in is about: the one containing
    /// the day before it, since a check-in looks back over the week just gone.
    func week(for checkin: WeeklyCheckin) -> WeeklyLogEntry? {
        guard let date = DateFormatting.date(fromISODate: checkin.checkinDate),
              let dayBefore = Calendar.current.date(byAdding: .day, value: -1, to: date) else { return nil }
        return weeks[DateFormatting.isoDate(DateFormatting.mondayOfWeek(containing: dayBefore))]
    }

    /// The week before that one, for "up/down on the week before".
    func previousWeek(of entry: WeeklyLogEntry) -> WeeklyLogEntry? {
        guard let prior = Calendar.current.date(byAdding: .day, value: -7, to: entry.weekStartDate) else { return nil }
        return weeks[DateFormatting.isoDate(prior)]
    }
}
