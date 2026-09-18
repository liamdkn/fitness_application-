import SwiftUI

struct StartWorkoutView: View {
    @State private var routine: Routine?
    @State private var todayDay: RoutineDay?
    @State private var isRestDay = false
    @State private var days: [RoutineDay] = []
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
    /// Each split day's exercise names, in position order - what the
    /// horizontally-scrolling day cards preview below "Your Split". Keyed
    /// by day id; a day with no entry here is either a rest day or hasn't
    /// loaded yet.
    @State private var dayExerciseNames: [UUID: [String]] = [:]
    @ObservedObject private var cardioMonitor = CardioSessionMonitor.shared
    private let routineRepository = RoutineRepository()
    private let workoutRepository = WorkoutRepository()
    private let offlineQueue = OfflineWorkoutQueue.shared
    private let checkinRepository = DailyCheckinRepository()
    private let muscleGroupVolumeRepository = MuscleGroupVolumeRepository()
    private let cardioSessionRepository = CardioSessionRepository()
    private let exerciseRepository = ExerciseRepository()

    /// True both when there's no scheduled day at all (`isRestDay`) and
    /// when today's scheduled day is itself a rest placeholder in the split
    /// (e.g. a 4-day Push/Pull/Legs/Rest rotation) - either way, there's
    /// nothing to start, so "Start Today's Workout" shouldn't show.
    private var isEffectivelyRestDay: Bool {
        isRestDay || todayDay?.label.caseInsensitiveCompare("Rest") == .orderedSame
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
                        if let todayDay {
                            Text(todayDay.label)
                                .font(.largeTitle.bold())
                        } else if isRestDay {
                            Text("Rest")
                                .font(.largeTitle.bold())
                        } else {
                            Text("Add a day to your split first.")
                                .foregroundStyle(.secondary)
                        }

                        if isEffectivelyRestDay {
                            Text("Rest day - no workout scheduled.")
                                .foregroundStyle(.secondary)
                        } else if todayDay != nil && activeWorkout == nil {
                            if todayCompletedWorkout != nil {
                                Label("Session Completed", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.headline)
                            } else {
                                // Hidden (not just disabled) whenever a
                                // workout is already active - the Resume
                                // banner above is the only way in, so a
                                // second one can't get started by mistake
                                // the way this one was.
                                Button {
                                    Task { await startWorkout() }
                                } label: {
                                    if isStarting {
                                        ProgressView()
                                    } else {
                                        Text("Start Today's Workout")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isStarting)
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Your Split")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                NavigationLink("Edit") {
                                    RoutineEditorView()
                                }
                                .font(.footnote)
                            }
                            if !days.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(alignment: .top, spacing: 12) {
                                        ForEach(days) { day in
                                            NavigationLink {
                                                RoutineDayDetailView(day: day)
                                            } label: {
                                                SplitDayCard(
                                                    day: day,
                                                    isToday: todayDay?.id == day.id,
                                                    exerciseNames: dayExerciseNames[day.id] ?? []
                                                )
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    // Always available (even on a rest day, or with no split
                    // set up) so an unplanned gym session isn't blocked on
                    // today's scheduled day - hidden only while another
                    // workout is already active, same rule as the split's
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

            if let checkin = try await checkinRepository.fetch(date: Date()) {
                if let routineDayId = checkin.routineDayId {
                    todayDay = days.first { $0.id == routineDayId }
                    isRestDay = false
                } else {
                    todayDay = nil
                    isRestDay = true
                }
            } else {
                todayDay = try await workoutRepository.nextRoutineDay(routineId: activeRoutine.id)
                isRestDay = false
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        // Offline-safe: checks the local queue before ever touching the
        // network, so a workout started at the gym with no signal still
        // shows its Resume banner if this view reloads mid-session.
        activeWorkout = try? await offlineQueue.fetchActive()
        let recentWorkouts = (try? await workoutRepository.fetchHistory(limit: 10)) ?? []
        todayCompletedWorkout = recentWorkouts.first { workout in
            workout.routineDayId == todayDay?.id
                && workout.endedAt != nil
                && Calendar.current.isDateInToday(workout.performedAt)
        }
        await CardioSessionMonitor.shared.refresh()
        await loadDeloadSignal(recentWorkouts: recentWorkouts)
        await loadVolumeFlags()
        await loadWeeklyCardioSummary()
        await loadDayExercisePreviews()
    }

    /// Each split day's exercise names, for the "Your Split" day cards -
    /// advisory only, so a card just shows without its preview list if this
    /// fails rather than blocking the rest of the tab.
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

    private func startWorkout() async {
        guard let todayDay else { return }
        // Defensive - the button that calls this is already hidden while
        // `activeWorkout` is set, but re-check here too so this can never
        // create a second concurrent workout regardless of UI state.
        guard activeWorkout == nil else { return }
        isStarting = true
        defer { isStarting = false }
        do {
            startedWorkout = try await offlineQueue.startWorkout(routineDayId: todayDay.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startOpenWorkout() async {
        guard activeWorkout == nil else { return }
        isStartingOpen = true
        defer { isStartingOpen = false }
        do {
            startedWorkout = try await offlineQueue.startWorkout(routineDayId: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// One day's card in the "Your Split" horizontal scroller - the day's
/// label plus a preview of what's on its workout menu, so you can see the
/// whole split at a glance without tapping into each day.
private struct SplitDayCard: View {
    let day: RoutineDay
    let isToday: Bool
    let exerciseNames: [String]

    private var previewLimit: Int { 5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(day.label)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if isToday {
                    Text("Today")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.15), in: Capsule())
                        .foregroundStyle(.blue)
                }
            }
            if exerciseNames.isEmpty {
                Text("Rest day")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(exerciseNames.prefix(previewLimit), id: \.self) { name in
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if exerciseNames.count > previewLimit {
                    Text("+\(exerciseNames.count - previewLimit) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(width: 170, alignment: .leading)
        .frame(minHeight: 130, alignment: .topLeading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        .foregroundStyle(.primary)
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
