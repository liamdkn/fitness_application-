import Foundation
import UserNotifications

/// What to nudge about, and when - a plain function so the timing and
/// wording can be checked without a notification centre.
nonisolated enum StepReminderPlan {
    enum Kind: String, CaseIterable {
        case afternoon = "step-goal-afternoon"
        case evening = "step-goal-evening"
    }

    struct Reminder {
        let kind: Kind
        let fireDate: Date
        let title: String
        let body: String
    }

    /// The afternoon check is at 2pm and only worth sending if less than this
    /// share of the target is done by then.
    static let afternoonMinutes = 14 * 60
    static let afternoonExpectedShare = 0.45
    /// A brisk walk, for turning "steps left" into "minutes of walking".
    static let stepsPerMinute = 100

    /// Nothing once the target's reached. Otherwise:
    /// - **evening** at `eveningMinutes`, saying how many steps are left;
    /// - **afternoon** at 2pm, only when behind pace and clear of the evening
    ///   one (two hours apart at least).
    /// Both are stamped with when the count was taken, because a local
    /// notification can't re-check at the moment it fires.
    static func reminders(
        steps: Int, target: Int, now: Date, eveningMinutes: Int, calendar: Calendar = .current
    ) -> [Reminder] {
        guard target > 0, steps < target else { return [] }
        let dayStart = calendar.startOfDay(for: now)
        let soon = now.addingTimeInterval(60)
        let clock = Date.FormatStyle(date: .omitted, time: .shortened).locale(.current)
        let asOf = now.formatted(clock)
        let remaining = target - steps
        var result: [Reminder] = []

        let eveningAt = dayStart.addingTimeInterval(TimeInterval(eveningMinutes * 60))
        if eveningAt > soon {
            let minutes = max(5, Int((Double(remaining) / Double(stepsPerMinute) / 5).rounded(.up)) * 5)
            var body = "\(format(remaining)) steps to go to hit \(format(target)) - about \(minutes) minutes of walking."
            if minutes > 90 { body += " Splitting it into a few walks would do it." }
            body += " (\(format(steps)) as of \(asOf).)"
            result.append(Reminder(kind: .evening, fireDate: eveningAt, title: "Steps left today", body: body))
        }

        let afternoonAt = dayStart.addingTimeInterval(TimeInterval(afternoonMinutes * 60))
        if afternoonAt > soon,
           afternoonAt.addingTimeInterval(2 * 3600) <= eveningAt,
           Double(steps) < Double(target) * afternoonExpectedShare {
            result.append(Reminder(
                kind: .afternoon,
                fireDate: afternoonAt,
                title: "Steps are running behind",
                body: "\(format(steps)) of \(format(target)) steps as of \(asOf). A walk this afternoon keeps today on track."
            ))
        }
        return result
    }

    private static func format(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }
}

/// Keeps the step-goal notifications in step with today's real count.
/// Local notifications can't re-check anything when they fire, so every
/// `refresh()` reads the current count from Health and replaces the pending
/// pair: on launch, on returning to the app, and in the background whenever
/// new steps land in Health (see `HealthKitManager.observeSteps`). When the
/// target's been reached the pending ones are removed, so there's no nudge
/// after you've already done it.
@MainActor
final class StepReminderService {
    static let shared = StepReminderService()

    private let healthKit = HealthKitManager()
    private let preferencesRepository = UserPreferencesRepository()
    private let goalsRepository = GoalsRepository()
    private let cardioSessionRepository = CardioStepSessionRepository()
    private var observing = false
    private var lastRefresh = Date.distantPast
    private var isRefreshing = false

    private init() {}

    /// Today's steps as the dashboard counts them (the chosen source, less
    /// machine-counted cardio steps when that's on). `nil` if Health can't be
    /// read right now, e.g. the phone is locked.
    func currentSteps(preferences: UserPreferences?) async -> Int? {
        let now = Date()
        let source = preferences?.stepSource ?? .merged
        guard let totals = try? await healthKit.fetchDailySteps(daysBack: 0, source: source) else { return nil }
        var steps = totals[Calendar.current.startOfDay(for: now)] ?? 0
        if preferences?.cardioStepExclusionEnabled == true,
           let sessions = try? await cardioSessionRepository.fetchSessions(date: now) {
            steps = max(steps - sessions.reduce(0) { $0 + $1.stepsDelta }, 0)
        }
        return steps
    }

    func startObserving() {
        guard !observing else { return }
        observing = true
        healthKit.observeSteps {
            await StepReminderService.shared.refresh()
            await WidgetSnapshotService.shared.refresh()
        }
    }

    /// `force` skips the once-a-minute throttle (Health can report new steps
    /// every few seconds while the app's open) - used after a settings change.
    func refresh(force: Bool = false) async {
        guard !isRefreshing, force || Date().timeIntervalSince(lastRefresh) > 60 else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        guard let preferences = try? await preferencesRepository.fetch() else { return }
        guard preferences.stepRemindersEnabled else {
            cancelAll()
            return
        }
        // No target (no active phase) means nothing to remind about.
        guard let target = (try? await goalsRepository.fetchCurrentGoal())??.stepTarget, target > 0 else {
            cancelAll()
            return
        }

        let now = Date()
        // If Health can't be read right now (the phone's locked, so its data
        // is encrypted) keep whatever's already scheduled rather than guess.
        guard let steps = await currentSteps(preferences: preferences) else { return }

        lastRefresh = now
        let plan = StepReminderPlan.reminders(
            steps: steps, target: target, now: now, eveningMinutes: preferences.stepReminderMinutes
        )
        let planned = Set(plan.map { $0.kind.rawValue })
        center.removePendingNotificationRequests(
            withIdentifiers: StepReminderPlan.Kind.allCases.map(\.rawValue).filter { !planned.contains($0) }
        )
        for reminder in plan {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate),
                repeats: false
            )
            try? await center.add(UNNotificationRequest(identifier: reminder.kind.rawValue, content: content, trigger: trigger))
        }
    }

    func cancelAll() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: StepReminderPlan.Kind.allCases.map(\.rawValue)
        )
    }
}
