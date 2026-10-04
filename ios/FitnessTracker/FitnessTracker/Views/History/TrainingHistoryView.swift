import SwiftUI

/// Strength workouts and cardio sessions merged into one chronological
/// list, sorted by date - the single "Training History" entry point on the
/// Train tab, replacing what used to be two separate screens.
struct TrainingHistoryView: View {
    /// When set, only the most recent `displayLimit` entries show, with a
    /// "More" link pushing an unrestricted instance of this same view -
    /// pass `nil` (as that pushed instance does) to show everything.
    var displayLimit: Int? = 7

    @State private var workouts: [Workout] = []
    @State private var dayLabels: [UUID: String] = [:]
    @State private var cardioSessions: [CardioTrackingSession] = []
    @State private var errorMessage: String?
    @State private var workoutToDelete: Workout?
    @State private var cardioSessionToDelete: CardioTrackingSession?
    @State private var completingCardioSession: CardioTrackingSession?

    private let workoutRepository = WorkoutRepository()
    private let routineRepository = RoutineRepository()
    private let cardioRepository = CardioSessionRepository()

    private enum Entry: Identifiable {
        case workout(Workout)
        case cardio(CardioTrackingSession)

        var id: String {
            switch self {
            case .workout(let workout): "workout-\(workout.id)"
            case .cardio(let session): "cardio-\(session.id)"
            }
        }

        var date: Date {
            switch self {
            case .workout(let workout): workout.performedAt
            case .cardio(let session): session.startedAt
            }
        }
    }

    private var entries: [Entry] {
        (workouts.map(Entry.workout) + cardioSessions.map(Entry.cardio))
            .sorted { $0.date > $1.date }
    }

    private var displayedEntries: [Entry] {
        guard let displayLimit else { return entries }
        return Array(entries.prefix(displayLimit))
    }

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(AppColor.error)
            }
            if !workouts.isEmpty {
                TotalWorkoutsHeadline(count: workouts.count)
            }
            if entries.isEmpty {
                if errorMessage == nil {
                    Text("No training logged yet.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(displayedEntries) { entry in
                    row(for: entry)
                }
                if let displayLimit, entries.count > displayLimit {
                    NavigationLink("More") {
                        TrainingHistoryView(displayLimit: nil)
                    }
                }
            }
        }
        .appScreen()
        .navigationTitle("Training History")
        .task { await load() }
        .sheet(item: $completingCardioSession) { session in
            CardioSessionEndSheet(
                initialStepsAfter: session.stepsAfter,
                initialAvgHeartRate: session.avgHeartRate,
                requiresSteps: session.cardioType.involvesSteps,
                allowsCancelActions: false,
                stepsBefore: session.stepsBefore,
                elapsedMinutes: session.elapsed() / 60,
                onSave: { stepsAfter, avgHeartRate in
                    await completeCardio(session, stepsAfter: stepsAfter, avgHeartRate: avgHeartRate)
                }
            )
        }
        .confirmationDialog(
            "Delete this workout? This can't be undone.",
            isPresented: Binding(get: { workoutToDelete != nil }, set: { if !$0 { workoutToDelete = nil } })
        ) {
            Button("Delete Workout", role: .destructive) {
                if let workout = workoutToDelete {
                    Task { await deleteWorkout(workout) }
                }
            }
        }
        .confirmationDialog(
            "Delete this cardio session? This can't be undone.",
            isPresented: Binding(get: { cardioSessionToDelete != nil }, set: { if !$0 { cardioSessionToDelete = nil } })
        ) {
            Button("Delete Session", role: .destructive) {
                if let session = cardioSessionToDelete {
                    Task { await deleteCardio(session) }
                }
            }
        }
    }

    @ViewBuilder
    private func row(for entry: Entry) -> some View {
        switch entry {
        case .workout(let workout):
            workoutRow(workout)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        workoutToDelete = workout
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
        case .cardio(let session):
            cardioRow(session)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        cardioSessionToDelete = session
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
        }
    }

    private func workoutRow(_ workout: Workout) -> some View {
        NavigationLink {
            WorkoutDetailView(workout: workout)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text(workout.routineDayId.flatMap { dayLabels[$0] } ?? workout.name ?? (workout.routineDayId == nil ? "Open Workout" : "Workout"))
                        .font(.subheadline.bold())
                } icon: {
                    Image(systemName: "dumbbell.fill")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text(workout.performedAt, style: .date)
                    if let duration = workout.duration {
                        Text(formattedDuration(duration))
                    } else {
                        Text("in progress")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func cardioRow(_ session: CardioTrackingSession) -> some View {
        let content = VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(session.cardioType.displayName)
                    .font(.subheadline.bold())
            } icon: {
                Image(systemName: "figure.run")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(session.startedAt, style: .date)
                if session.endedAt != nil {
                    Text(formattedDuration(session.elapsed()))
                } else {
                    Text("in progress")
                }
                if let avgHeartRate = session.avgHeartRate {
                    Text("\(avgHeartRate) bpm avg")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if isMissingDetails(session) {
                Text("Tap to add \(session.cardioType.involvesSteps ? "steps & " : "")heart rate")
                    .font(.caption)
                    .foregroundStyle(AppColor.accent)
            }
        }

        if isMissingDetails(session) {
            Button {
                completingCardioSession = session
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    /// A session whose type never collects steps (Bike/Rowing/Swimming/
    /// etc.) isn't "missing" steps just because `stepsAfter` is nil - that's
    /// simply not applicable to it, so only heart rate (and steps, when
    /// this type actually tracks them) count toward missing.
    private func isMissingDetails(_ session: CardioTrackingSession) -> Bool {
        guard session.endedAt != nil else { return false }
        // A session imported from the Watch has what the Watch recorded; it has
        // no steps-now to type in and shouldn't nag for them.
        guard session.source == "app" else { return false }
        let missingSteps = session.cardioType.involvesSteps && session.stepsAfter == nil
        return missingSteps || session.avgHeartRate == nil
    }

    private func load() async {
        do {
            let fetched = try await workoutRepository.fetchHistory()
            workouts = fetched
            OfflineReferenceCache.save(fetched, key: "workout-history")
            let routineDayIds = Set(fetched.compactMap(\.routineDayId))
            for dayId in routineDayIds where dayLabels[dayId] == nil {
                if let day = try? await routineRepository.fetchDay(id: dayId) {
                    dayLabels[dayId] = day.label
                }
            }
            OfflineReferenceCache.save(dayLabels, key: "workout-history-day-labels")
        } catch {
            // Offline fallback: show the last successfully loaded list
            // (same "last known good" pattern ActiveWorkoutViewModel uses
            // for the exercise library) rather than an empty error screen.
            if let cached = OfflineReferenceCache.load([Workout].self, key: "workout-history") {
                workouts = cached
                dayLabels = OfflineReferenceCache.load([UUID: String].self, key: "workout-history-day-labels") ?? [:]
            } else {
                errorMessage = error.localizedDescription
            }
        }

        do {
            cardioSessions = try await cardioRepository.fetchHistory()
        } catch {
            if errorMessage == nil {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deleteWorkout(_ workout: Workout) async {
        do {
            try await workoutRepository.deleteWorkout(workoutId: workout.id)
            workouts.removeAll { $0.id == workout.id }
        } catch {
            errorMessage = error.localizedDescription
        }
        workoutToDelete = nil
    }

    private func completeCardio(_ session: CardioTrackingSession, stepsAfter: Int?, avgHeartRate: Int) async {
        do {
            let updated = try await cardioRepository.updateSessionDetails(
                sessionId: session.id,
                stepsAfter: stepsAfter,
                avgHeartRate: avgHeartRate
            )
            if let index = cardioSessions.firstIndex(where: { $0.id == updated.id }) {
                cardioSessions[index] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteCardio(_ session: CardioTrackingSession) async {
        do {
            try await cardioRepository.discardSession(sessionId: session.id)
            cardioSessions.removeAll { $0.id == session.id }
        } catch {
            errorMessage = error.localizedDescription
        }
        cardioSessionToDelete = nil
    }

    private func formattedDuration(_ interval: TimeInterval) -> String {
        "\(Int(interval) / 60) min"
    }
}

/// Big, centered "how many strength workouts total" - a proud milestone
/// number at the top of the list, not part of the merged workout/cardio
/// `entries` count (cardio sessions aren't "workouts").
private struct TotalWorkoutsHeadline: View {
    let count: Int

    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.system(size: 44, weight: .bold, design: .rounded))
            Text("Total Workouts")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}
