import SwiftUI

struct WorkoutHistoryView: View {
    @State private var workouts: [Workout] = []
    @State private var dayLabels: [UUID: String] = [:]
    @State private var errorMessage: String?
    @State private var workoutToDelete: Workout?
    private let workoutRepository = WorkoutRepository()
    private let routineRepository = RoutineRepository()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("History")
                .font(.headline)
                .foregroundStyle(.secondary)

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            } else if workouts.isEmpty {
                Text("No workouts logged yet.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(workouts) { workout in
                        HStack {
                            NavigationLink {
                                WorkoutDetailView(workout: workout)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(workout.routineDayId.flatMap { dayLabels[$0] } ?? workout.name ?? (workout.routineDayId == nil ? "Open Workout" : "Workout"))
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.primary)
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
                            Spacer()
                            Button {
                                workoutToDelete = workout
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                        Divider()
                    }
                }
            }
        }
        .task { await load() }
        .confirmationDialog(
            "Delete this workout? This can't be undone.",
            isPresented: Binding(get: { workoutToDelete != nil }, set: { if !$0 { workoutToDelete = nil } })
        ) {
            Button("Delete Workout", role: .destructive) {
                if let workout = workoutToDelete {
                    Task { await delete(workout) }
                }
            }
        }
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
    }

    private func delete(_ workout: Workout) async {
        do {
            try await workoutRepository.deleteWorkout(workoutId: workout.id)
            workouts.removeAll { $0.id == workout.id }
        } catch {
            errorMessage = error.localizedDescription
        }
        workoutToDelete = nil
    }

    private func formattedDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        return "\(minutes) min"
    }
}
