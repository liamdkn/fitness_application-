import SwiftUI

struct StartWorkoutView: View {
    @State private var routine: Routine?
    @State private var days: [RoutineDay] = []
    @State private var weeklySchedule: [WeeklyScheduleDay] = []
    @State private var hasCenteredOnToday = false
    @State private var errorMessage: String?
    @State private var startedWorkout: Workout?
    @State private var activeWorkout: Workout?
    @State private var todayCompletedWorkout: Workout?
    @State private var isStarting = false
    @State private var isStartingOpen = false
    @State private var deloadSignal: DeloadSignal?
    @State private var volumeFlags: [MuscleGroupVolumeFlag] = []
    @State private var weeklyCardioMinutes = 0
    @State private var weeklyCardioSessionCount = 0
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

    private func routineDay(for slot: WeeklyScheduleDay) -> RoutineDay? {
        guard let id = slot.routineDayId else { return nil }
        return days.first { $0.id == id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
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
                        .buttonStyle(.borderedProminent)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("This Week")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                NavigationLink("Edit") {
                                    RoutineEditorView()
                                }
                                .font(.footnote)
                            }

                            if !weeklySchedule.isEmpty {
                                ScrollViewReader { proxy in
                                    ScrollView(.horizontal) {
                                        LazyHStack(spacing: 16) {
                                            ForEach(weeklySchedule) { slot in
                                                WeekDayCard(
                                                    slot: slot,
                                                    routineDay: routineDay(for: slot),
                                                    exerciseNames: routineDay(for: slot).flatMap { dayExerciseNames[$0.id] } ?? [],
                                                    isToday: slot.weekday == todaysWeekday,
                                                    hasActiveWorkout: activeWorkout != nil,
                                                    isCompletedToday: todayCompletedWorkout != nil,
                                                    isStarting: isStarting,
                                                    onStartWorkout: { day in Task { await startWorkout(routineDayId: day.id) } }
                                                )
                                                .id(slot.weekday)
                                                .containerRelativeFrame(.horizontal, count: 1, spacing: 16)
                                            }
                                        }
                                        .scrollTargetLayout()
                                    }
                                    .scrollTargetBehavior(.viewAligned)
                                    .scrollIndicators(.hidden)
                                    // A default starting position only, not a
                                    // reset every reappearance - `scrollTo`'s
                                    // target frame isn't resolved yet on the
                                    // very first layout pass if called
                                    // straight from `onAppear`, so this
                                    // defers one runloop turn; `hasCentered`
                                    // then keeps it from re-firing and
                                    // yanking the carousel back to today if
                                    // the user had manually scrolled away.
                                    .onAppear {
                                        guard !hasCenteredOnToday else { return }
                                        hasCenteredOnToday = true
                                        DispatchQueue.main.async {
                                            proxy.scrollTo(todaysWeekday, anchor: .center)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Always available (even on a rest day, or with no split
                    // set up) so an unplanned gym session isn't blocked on
                    // today's scheduled day - hidden only while another
                    // workout is already active, same rule as a day card's
                    // own Start button.
                    if activeWorkout == nil {
                        Button {
                            Task { await startOpenWorkout() }
                        } label: {
                            if isStartingOpen {
                                ProgressView()
                            } else {
                                Label("Start Open Workout", systemImage: "bolt.fill")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isStartingOpen)
                    }

                    DashboardCard(title: "Cardio") {
                        VStack(spacing: 12) {
                            VStack(spacing: 2) {
                                Text("\(weeklyCardioMinutes)")
                                    .font(.system(size: 44, weight: .bold, design: .rounded))
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
                            } else {
                                NavigationLink("Start Cardio Session") {
                                    StartCardioSessionView()
                                }
                            }

                            HStack {
                                Text("Sessions this week")
                                Spacer()
                                Text("\(weeklyCardioSessionCount)")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    NavigationLink {
                        TrainingHistoryView()
                    } label: {
                        Label("Training History", systemImage: "clock.arrow.circlepath")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    NavigationLink {
                        ExerciseLibraryView()
                    } label: {
                        Label("Exercise Library", systemImage: "dumbbell")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .navigationTitle("Training")
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
        preferredGymId = try? await preferencesRepository.fetch().preferredGymId
        await CardioSessionMonitor.shared.refresh()
        await loadDeloadSignal(recentWorkouts: recentWorkouts)
        await loadVolumeFlags()
        await loadWeeklyCardioSummary()
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
            weeklyCardioSessionCount = thisWeek.count
        } catch {
            // Advisory only - don't block the Train tab on this failing.
        }
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
}

/// One weekday's card in the "This Week" carousel - a workout day previews
/// its exercises and offers to start it (today's card additionally shows
/// "Session Completed" once it's done); an active rest day names its
/// cardio type and offers to start that; a rest day is just a plain
/// placeholder. None of the start actions are limited to today - the split
/// is a plan, not a lock (see `actionRow`). Enlarged to near-full-width so
/// the carousel reads as one day at a time, snapping to whichever is
/// centered.
private struct WeekDayCard: View {
    let slot: WeeklyScheduleDay
    let routineDay: RoutineDay?
    let exerciseNames: [String]
    let isToday: Bool
    let hasActiveWorkout: Bool
    let isCompletedToday: Bool
    let isStarting: Bool
    let onStartWorkout: (RoutineDay) -> Void

    private var previewLimit: Int { 6 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(slot.weekdayName)
                    .font(.title3.bold())
                if isToday {
                    Text("Today")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.15), in: Capsule())
                        .foregroundStyle(.blue)
                }
                Spacer()
            }

            switch slot.dayType {
            case .workout:
                if let routineDay {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(routineDay.label)
                            .font(.headline)
                        if exerciseNames.isEmpty {
                            Text("No exercises added yet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
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
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    actionRow(routineDay: routineDay)
                } else {
                    Text("No day linked - edit this in your split.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            case .activeRest:
                VStack(alignment: .leading, spacing: 6) {
                    Label(slot.cardioType?.displayName ?? "Active Rest", systemImage: "figure.run")
                        .font(.headline)
                    Text("Active rest day")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                // Not gated to today - a scheduled run/walk is just as
                // startable a day early or a day late as a workout is (see
                // `actionRow`'s own reasoning below), only actually blocked
                // while another workout is already in progress.
                if !hasActiveWorkout {
                    NavigationLink {
                        StartCardioSessionView(initialCardioType: slot.cardioType ?? .inclineTreadmill)
                    } label: {
                        Text("Start Cardio Session")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                }
            case .rest:
                Text("Rest Day")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding()
        .frame(minHeight: 220, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18))
        .foregroundStyle(.primary)
        .overlay(alignment: .bottomTrailing) {
            if slot.dayType == .workout, let routineDay {
                menuButton(routineDay: routineDay)
            }
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
        .padding(12)
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
                .foregroundStyle(.green)
                .font(.subheadline.bold())
        } else {
            Button {
                onStartWorkout(routineDay)
            } label: {
                if isStarting {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Start Workout")
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 10)
            .buttonStyle(.borderedProminent)
            .disabled(isStarting)
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
                    .foregroundStyle(.orange)
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
