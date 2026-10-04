import SwiftUI

struct StartWorkoutView: View {
    @State private var routine: Routine?
    @State private var days: [RoutineDay] = []
    @State private var weeklySchedule: [WeeklyScheduleDay] = []
    /// Which day's card is showing; nil means today.
    @State private var selectedWeekday: Int?
    /// Which way the last day change moved along the strip - the card slides
    /// in from that side.
    @State private var slideForward = true
    @Namespace private var zoomNamespace
    /// Weekdays (1 = Sunday) with a finished workout this week.
    @State private var completedWeekdays: Set<Int> = []
    @State private var errorMessage: String?
    @State private var startedWorkout: Workout?
    @State private var activeWorkout: Workout?
    @State private var todayCompletedWorkout: Workout?
    @State private var isStarting = false
    @State private var isStartingOpen = false
    @State private var deloadSignal: DeloadSignal?
    @State private var volumeFlags: [MuscleGroupVolumeFlag] = []
    @State private var weeklyCardioMinutes = 0
    /// The Running card: km run this week (Watch runs), what the plan wanted
    /// this week, and which week of the plan it is. Plan values are nil
    /// without a plan.
    @State private var weeklyRunKm = 0.0
    @State private var weeklyPlannedKm: Double?
    @State private var runningPlanWeek: Int?
    private let runningPlanRepository = RunningPlanRepository()
    @State private var preferredGymId: UUID?
    /// Each workout day's exercise names, in position order - what a
    /// carousel card previews. Keyed by `RoutineDay.id`.
    @State private var dayExerciseNames: [UUID: [String]] = [:]
    @ObservedObject private var cardioMonitor = CardioSessionMonitor.shared
    private let routineRepository = RoutineRepository()
    private let scheduleRepository = WeeklyScheduleRepository()
    private let workoutRepository = WorkoutRepository()
    private let offlineQueue = OfflineWorkoutQueue.shared
    private let checkinRepository = DailyCheckinRepository()
    private let preferencesRepository = UserPreferencesRepository()
    private let muscleGroupVolumeRepository = MuscleGroupVolumeRepository()
    private let cardioSessionRepository = CardioSessionRepository()
    private let exerciseRepository = ExerciseRepository()

    private var todaysWeekday: Int { Calendar.current.component(.weekday, from: Date()) }

    /// Monday first, matching how the week is read, rather than the
    /// Sunday-first order the weekday numbers fall in.
    private var orderedSchedule: [WeeklyScheduleDay] {
        let order = [2, 3, 4, 5, 6, 7, 1]
        return weeklySchedule.sorted { (order.firstIndex(of: $0.weekday) ?? 0) < (order.firstIndex(of: $1.weekday) ?? 0) }
    }

    /// An active-rest day's own card already has a Start Cardio Session
    /// button (with that day's cardio type chosen), so the Cardio card skips
    /// its own rather than showing two.
    private var selectedDayOffersCardio: Bool {
        let weekday = selectedWeekday ?? todaysWeekday
        return activeWorkout == nil && weeklySchedule.contains { $0.weekday == weekday && $0.dayType == .activeRest }
    }

    private func routineDay(for slot: WeeklyScheduleDay) -> RoutineDay? {
        guard let id = slot.routineDayId else { return nil }
        return days.first { $0.id == id }
    }

    var body: some View {
        AppNavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(AppColor.error)
                    }

                    if let activeWorkout {
                        NavigationLink {
                            ActiveWorkoutView(workout: activeWorkout)
                        } label: {
                            DashboardCard {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Workout In Progress")
                                            .fontWeight(.semibold)
                                        Text("Started \(activeWorkout.startedAt, style: .relative) ago - Tap to Resume")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    if let deloadSignal, deloadSignal.severity != .none {
                        DeloadBanner(signal: deloadSignal)
                    }

                    if !volumeFlags.isEmpty {
                        VolumeCheckCard(flags: volumeFlags)
                    }

                    if routine == nil {
                        Text("Set up your split to get started.")
                            .foregroundStyle(.secondary)
                        NavigationLink("Set Up My Split") {
                            RoutineEditorView()
                        }
                        .buttonStyle(.appPrimary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            if !weeklySchedule.isEmpty {
                                WeekStrip(
                                    slots: orderedSchedule,
                                    selectedWeekday: selectedWeekday ?? todaysWeekday,
                                    todaysWeekday: todaysWeekday,
                                    completedWeekdays: completedWeekdays,
                                    onSelect: { weekday in
                                        let order = orderedSchedule.map(\.weekday)
                                        let old = order.firstIndex(of: selectedWeekday ?? todaysWeekday) ?? 0
                                        slideForward = (order.firstIndex(of: weekday) ?? 0) >= old
                                        withAnimation(.snappy(duration: 0.32)) { selectedWeekday = weekday }
                                    }
                                )
                                if let slot = orderedSchedule.first(where: { $0.weekday == (selectedWeekday ?? todaysWeekday) }) {
                                    WeekDayCard(
                                        slot: slot,
                                        routineDay: routineDay(for: slot),
                                        exerciseNames: routineDay(for: slot).flatMap { dayExerciseNames[$0.id] } ?? [],
                                        isToday: slot.weekday == todaysWeekday,
                                        hasActiveWorkout: activeWorkout != nil,
                                        isCompletedToday: todayCompletedWorkout != nil,
                                        isCompleted: completedWeekdays.contains(slot.weekday),
                                        isStarting: isStarting,
                                        isStartingOpen: isStartingOpen,
                                        onStartWorkout: { day in Task { await startWorkout(routineDayId: day.id) } },
                                        onStartOpenWorkout: { Task { await startOpenWorkout() } }
                                    )
                                    .id(slot.weekday)
                                    .transition(.asymmetric(
                                        insertion: .move(edge: slideForward ? .trailing : .leading).combined(with: .opacity),
                                        removal: .opacity
                                    ))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    DashboardCard(title: "Cardio") {
                        VStack(spacing: 12) {
                            VStack(spacing: 2) {
                                Text("\(weeklyCardioMinutes)")
                                    .font(.system(size: 44, weight: .bold, design: .rounded))
                                    .rolling(Double(weeklyCardioMinutes))
                                Text("minutes this week")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)

                            if let activeSession = cardioMonitor.activeSession {
                                NavigationLink {
                                    CardioSessionLiveView(session: activeSession)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Cardio Session In Progress")
                                                .fontWeight(.semibold)
                                            Text("\(activeSession.cardioType.displayName) - Tap to Resume")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                }
                            } else if !selectedDayOffersCardio {
                                NavigationLink {
                                    StartCardioSessionView()
                                } label: {
                                    Text("Start Cardio Session")
                                }
                                .buttonStyle(.appPrimary)
                            }
                        }
                    }

                    DashboardCard(title: "Running") {
                        VStack(spacing: 12) {
                            VStack(spacing: 2) {
                                Text(Self.kmText(weeklyRunKm))
                                    .font(.system(size: 44, weight: .bold, design: .rounded))
                                    .rolling(weeklyRunKm)
                                Text("km this week")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let planned = weeklyPlannedKm, planned > 0 {
                                    Text("of \(Self.kmText(planned)) km planned\(runningPlanWeek.map { " \u{00b7} Week \($0)" } ?? "")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if let week = runningPlanWeek {
                                    Text("Week \(week) of your plan")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity)

                            NavigationLink {
                                RunningPlanView()
                                    .zoomDestination(id: "running-plan", in: zoomNamespace)
                            } label: {
                                Text("Running Plan")
                            }
                            .buttonStyle(.appPrimary)
                            .zoomSource(id: "running-plan", in: zoomNamespace)
                        }
                    }

                    NavigationLink {
                        TrainingHistoryView()
                    } label: {
                        Label("Training History", systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appSecondary)

                    NavigationLink {
                        ExerciseLibraryView()
                    } label: {
                        Label("Exercise Library", systemImage: "dumbbell")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appSecondary)
                }
                .padding()
            }
            .appScreen()
            .navigationTitle("Training")
            .toolbar {
                if routine != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink("Edit") {
                            RoutineEditorView()
                        }
                        .appToolbarTint()
                    }
                }
            }
            // `.onAppear`, not `.task` - this view stays mounted as the Train
            // tab's root, so `.task` would only ever fire once. `.onAppear`
            // re-fires whenever a pushed screen (a routine day, an active
            // workout) pops back to this one, which is exactly when
            // `activeWorkout` needs to be re-checked - otherwise finishing
            // or canceling a resumed workout would leave a stale "Workout
            // In Progress" banner showing until the tab was reloaded some
            // other way.
            .onAppear { Task { await load() } }
            .navigationDestination(item: $startedWorkout) { workout in
                ActiveWorkoutView(workout: workout)
            }
        }
    }

    private func load() async {
        do {
            let activeRoutine = try await routineRepository.fetchActiveRoutine()
            routine = activeRoutine
            guard let activeRoutine else { return }
            days = try await routineRepository.fetchDays(routineId: activeRoutine.id)
            weeklySchedule = try await scheduleRepository.fetchSchedule(routineId: activeRoutine.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        // Offline-safe: checks the local queue before ever touching the
        // network, so a workout started at the gym with no signal still
        // shows its Resume banner if this view reloads mid-session.
        activeWorkout = try? await offlineQueue.fetchActive()
        let recentWorkouts = (try? await workoutRepository.fetchHistory(limit: 10)) ?? []
        let todaysRoutineDayId = weeklySchedule.first { $0.weekday == todaysWeekday }?.routineDayId
        todayCompletedWorkout = recentWorkouts.first { workout in
            workout.routineDayId == todaysRoutineDayId
                && workout.endedAt != nil
                && Calendar.current.isDateInToday(workout.performedAt)
        }
        let weekStart = Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        completedWeekdays = Set(
            recentWorkouts
                .filter { $0.endedAt != nil && $0.performedAt >= weekStart }
                .map { Calendar.current.component(.weekday, from: $0.performedAt) }
        )
        preferredGymId = try? await preferencesRepository.fetch().preferredGymId
        await CardioSessionMonitor.shared.refresh()
        await loadDeloadSignal(recentWorkouts: recentWorkouts)
        await loadVolumeFlags()
        await loadWeeklyCardioSummary()
        await loadRunningSummary()
        await loadDayExercisePreviews()
    }

    /// Each workout day's exercise names, for its carousel card - advisory
    /// only, so a card just shows without its preview list if this fails
    /// rather than blocking the rest of the tab.
    private func loadDayExercisePreviews() async {
        guard !days.isEmpty else { return }
        guard let allExercises = try? await exerciseRepository.fetchAll() else { return }
        let namesById = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.id, $0.name) })
        var result: [UUID: [String]] = [:]
        for day in days {
            let dayExercises = (try? await routineRepository.fetchDayExercises(routineDayId: day.id)) ?? []
            result[day.id] = dayExercises
                .sorted { $0.position < $1.position }
                .compactMap { namesById[$0.exerciseId] }
        }
        dayExerciseNames = result
    }

    /// An unplanned session with no routine day behind it - offered on rest
    /// days, where there's no planned workout to start.
    private func startOpenWorkout() async {
        guard activeWorkout == nil else { return }
        isStartingOpen = true
        defer { isStartingOpen = false }
        do {
            startedWorkout = try await offlineQueue.startWorkout(routineDayId: nil, gymId: preferredGymId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadDeloadSignal(recentWorkouts: [Workout]) async {
        do {
            let recentCheckins = try await checkinRepository.fetchRecent(days: 10)
            deloadSignal = DeloadAdvisor.evaluate(recentCheckins: recentCheckins, recentWorkouts: Array(recentWorkouts.prefix(5)))
        } catch {
            // Advisory only - don't block the Train tab on this failing.
        }
    }

    private func loadWeeklyCardioSummary() async {
        do {
            let calendar = Calendar.current
            let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
            let sessions = try await cardioSessionRepository.fetchHistory(limit: 50)
            let thisWeek = sessions.filter { $0.endedAt != nil && $0.startedAt >= weekStart }
            weeklyCardioMinutes = Int(thisWeek.reduce(0.0) { $0 + $1.elapsed() } / 60)
        } catch {
            // Advisory only - don't block the Train tab on this failing.
        }
    }

    /// Km run this week from imported Watch runs, against this week's planned
    /// distance. Advisory - the card just shows what it has if this fails.
    private func loadRunningSummary() async {
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? Date()
        if let runs = try? await runningPlanRepository.fetchRuns(from: weekStart) {
            weeklyRunKm = runs.compactMap(\.distanceMeters).reduce(0, +) / 1000
        }
        guard let plan = try? await runningPlanRepository.fetchActivePlan() else {
            weeklyPlannedKm = nil
            runningPlanWeek = nil
            return
        }
        let planStartWeek = calendar.dateInterval(of: .weekOfYear, for: plan.start)?.start ?? plan.start
        let weeksIn = calendar.dateComponents([.weekOfYear], from: planStartWeek, to: weekStart).weekOfYear ?? 0
        runningPlanWeek = weeksIn >= 0 ? plan.firstWeekNumber + weeksIn : nil
        if let planned = try? await runningPlanRepository.fetchPlannedRuns(planId: plan.id) {
            weeklyPlannedKm = planned
                .filter { $0.day >= weekStart && $0.day < weekEnd }
                .compactMap(\.targetDistanceKm)
                .reduce(0, +)
        }
    }

    /// "12.4", or "12" when it's a whole number.
    private static func kmText(_ km: Double) -> String {
        let text = String(format: "%.1f", km)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }

    private func loadVolumeFlags() async {
        do {
            let rows = try await muscleGroupVolumeRepository.fetchRecentWeeks()
            volumeFlags = MuscleGroupVolumeAnalyzer.evaluate(rows: rows)
        } catch {
            // Advisory only - don't block the Train tab on this failing.
        }
    }

    private func startWorkout(routineDayId: UUID) async {
        // Defensive - the button that calls this is already hidden while
        // `activeWorkout` is set, but re-check here too so this can never
        // create a second concurrent workout regardless of UI state.
        guard activeWorkout == nil else { return }
        isStarting = true
        defer { isStarting = false }
        do {
            startedWorkout = try await offlineQueue.startWorkout(routineDayId: routineDayId, gymId: preferredGymId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// The card under the week strip for the selected day - a workout day
/// previews its exercises and offers to start it (today's card additionally
/// shows "Session Completed" once it's done); an active rest day names its
/// cardio type and offers to start that; a rest day is just a plain
/// placeholder. None of the start actions are limited to today - the split
/// is a plan, not a lock (see `actionRow`).
private struct WeekDayCard: View {
    let slot: WeeklyScheduleDay
    let routineDay: RoutineDay?
    let exerciseNames: [String]
    let isToday: Bool
    let hasActiveWorkout: Bool
    let isCompletedToday: Bool
    /// This particular day has a finished workout this week.
    let isCompleted: Bool
    let isStarting: Bool
    let isStartingOpen: Bool
    let onStartWorkout: (RoutineDay) -> Void
    let onStartOpenWorkout: () -> Void

    private var previewLimit: Int { 6 }

    /// The card's own corner radius - its start buttons use the same one so
    /// they read as part of the card's shape rather than a pill inside it.
    static let cornerRadius = AppButtonStyle.largeCornerRadius

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The week strip above already says which day this is, so the
            // card leads with what the day holds instead.
            switch slot.dayType {
            case .workout:
                if let routineDay {
                    titleRow {
                        Text(routineDay.label)
                            .font(.title3.bold())
                    } trailing: {
                        menuButton(routineDay: routineDay)
                    }
                    if exerciseNames.isEmpty {
                        Text("No exercises added yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(exerciseNames.prefix(previewLimit), id: \.self) { name in
                                Text(name)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            if exerciseNames.count > previewLimit {
                                Text("+\(exerciseNames.count - previewLimit) more")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    actionRow(routineDay: routineDay)
                } else {
                    titleRow {
                        Text("No day linked")
                            .font(.title3.bold())
                    } trailing: {
                        EmptyView()
                    }
                    Text("Edit this in your split.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            case .activeRest:
                titleRow {
                    Label(slot.cardioType?.displayName ?? "Active Rest", systemImage: "figure.run")
                        .font(.title3.bold())
                } trailing: {
                    EmptyView()
                }
                Text("Active rest day")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Not gated to today - a scheduled run/walk is just as
                // startable a day early or a day late as a workout is (see
                // `actionRow`'s own reasoning below), only actually blocked
                // while another workout is already in progress.
                if !hasActiveWorkout {
                    NavigationLink {
                        StartCardioSessionView(initialCardioType: slot.cardioType ?? .inclineTreadmill)
                    } label: {
                        Text("Start Cardio Session")
                    }
                    .buttonStyle(.appPrimary)
                }
            case .rest:
                titleRow {
                    Label("Rest day", systemImage: "moon.zzz.fill")
                        .font(.title3.bold())
                        .foregroundStyle(.secondary)
                } trailing: {
                    EmptyView()
                }
                // Takes the place of the planned workout's Start button.
                if !hasActiveWorkout {
                    Button {
                        onStartOpenWorkout()
                    } label: {
                        Group {
                            if isStartingOpen {
                                ProgressView()
                            } else {
                                Text("Start Open Workout")
                            }
                        }
                    }
                    .buttonStyle(.appPrimary)
                    .disabled(isStartingOpen)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .appCard(cornerRadius: Self.cornerRadius)
        .foregroundStyle(.primary)
    }

    /// The card's heading: the day's own title, then Today / Done badges, and
    /// whatever trailing control the day has (the exercise menu).
    private func titleRow<Title: View, Trailing: View>(
        @ViewBuilder title: () -> Title, @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 8) {
            title()
            if isToday {
                Text("Today")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppColor.accent.opacity(0.15), in: Capsule())
                    .foregroundStyle(AppColor.accent)
            }
            Spacer()
            if isCompleted {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(AppColor.success)
            }
            trailing()
        }
    }

    /// The day's exercise "menu" (`RoutineDayDetailView`) - kept to a small,
    /// deliberate corner affordance rather than making the whole card a
    /// `NavigationLink`, so brushing past the exercise preview doesn't
    /// accidentally navigate away from the "Start Workout" button beneath it.
    private func menuButton(routineDay: RoutineDay) -> some View {
        NavigationLink {
            RoutineDayDetailView(day: routineDay)
        } label: {
            Image(systemName: "ellipsis")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .background(.fill.tertiary, in: Circle())
        }
        .buttonStyle(.plain)
    }

    /// Available on every workout-type card, not just today's - the split
    /// is a plan, not a lock: catching up on a missed day, or getting ahead
    /// on tomorrow's before you're too tired later, both start the same way
    /// `startWorkout(routineDayId:)` always did (it's never been date-gated
    /// server-side, only this card was). Only actually blocked while
    /// another workout is already active - same single-active-session rule
    /// as everywhere else in Train. "Session Completed" stays specific to
    /// today, since that's the only day with a real "already done today"
    /// answer to show.
    @ViewBuilder
    private func actionRow(routineDay: RoutineDay) -> some View {
        if hasActiveWorkout {
            EmptyView()
        } else if isToday && isCompletedToday {
            Label("Session Completed", systemImage: "checkmark.circle.fill")
                .foregroundStyle(AppColor.success)
                .font(.subheadline.bold())
        } else {
            Button {
                onStartWorkout(routineDay)
            } label: {
                // Padding inside the label, so the button itself is tall
                // enough for the card's corner radius to read as a rounded
                // rectangle rather than saturating into a pill.
                Group {
                    if isStarting {
                        ProgressView()
                    } else {
                        Text("Start Workout")
                    }
                }
            }
            .buttonStyle(.appPrimary)
            .disabled(isStarting)
        }
    }
}

/// The week at a glance: a pill per day with what it holds (workout,
/// active rest, rest), today marked, and a tick on days already trained.
/// Tapping one shows that day's card below.
private struct WeekStrip: View {
    let slots: [WeeklyScheduleDay]
    let selectedWeekday: Int
    let todaysWeekday: Int
    let completedWeekdays: Set<Int>
    let onSelect: (Int) -> Void

    @Namespace private var selection

    var body: some View {
        HStack(spacing: 6) {
            ForEach(slots) { slot in
                let isSelected = slot.weekday == selectedWeekday
                let isToday = slot.weekday == todaysWeekday
                Button {
                    onSelect(slot.weekday)
                } label: {
                    VStack(spacing: 5) {
                        Text(String(slot.weekdayName.prefix(3)))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(isSelected ? .white : (isToday ? AppColor.accent : .secondary))
                        Image(systemName: icon(for: slot.dayType))
                            .font(.subheadline)
                            .foregroundStyle(isSelected ? .white : .primary.opacity(slot.dayType == .rest ? 0.35 : 0.9))
                        Image(systemName: completedWeekdays.contains(slot.weekday) ? "checkmark.circle.fill" : "circle.fill")
                            .font(.system(size: completedWeekdays.contains(slot.weekday) ? 11 : 4))
                            .foregroundStyle(
                                completedWeekdays.contains(slot.weekday)
                                    ? (isSelected ? Color.white : AppColor.success)
                                    : (isToday ? AppColor.accent : Color.clear)
                            )
                            .frame(height: 11)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background {
                        // One highlight shared by all days, so changing day
                        // slides it along the strip rather than swapping.
                        if isSelected {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(AppColor.accent)
                                .matchedGeometryEffect(id: "selectedDay", in: selection)
                        }
                    }
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(slot.weekdayName), \(label(for: slot.dayType))\(completedWeekdays.contains(slot.weekday) ? ", done" : "")")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
    }

    private func icon(for type: ScheduledDayType) -> String {
        switch type {
        case .workout: return "dumbbell.fill"
        case .activeRest: return "figure.run"
        case .rest: return "moon.zzz.fill"
        }
    }

    private func label(for type: ScheduledDayType) -> String {
        switch type {
        case .workout: return "workout"
        case .activeRest: return "active rest"
        case .rest: return "rest"
        }
    }
}

private struct VolumeCheckCard: View {
    let flags: [MuscleGroupVolumeFlag]

    var body: some View {
        DashboardCard(title: "Volume Check") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(flags, id: \.muscleGroup) { flag in
                    HStack {
                        Text(displayName(for: flag.muscleGroup))
                        Spacer()
                        Text("\(Int(flag.currentVolumeKg))kg this week vs \(Int(flag.trailingAverageVolumeKg))kg avg")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func displayName(for muscleGroup: String) -> String {
        MuscleGroup(rawValue: muscleGroup)?.displayName ?? muscleGroup.capitalized
    }
}

private struct DeloadBanner: View {
    let signal: DeloadSignal

    private var title: String {
        signal.severity == .recommended ? "Deload recommended" : "Consider a deload"
    }

    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(AppColor.warning)
                ForEach(signal.reasons, id: \.self) { reason in
                    Text("\u{2022} \(reason)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Consider cutting volume and intensity back for a week before your next session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
