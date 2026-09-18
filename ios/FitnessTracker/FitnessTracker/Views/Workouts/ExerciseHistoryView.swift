import SwiftUI

/// One past session's worth of sets (and note, if any) for a single
/// exercise - `ExerciseHistoryView`'s row unit. Built from the union of
/// logged sets and notes so a session where a note was added but nothing
/// was actually logged (e.g. planned, then skipped) still shows up.
private struct ExerciseHistoryEntry: Identifiable {
    let workoutId: UUID
    let performedAt: Date
    let sets: [WorkoutSet]
    let note: String?
    var id: UUID { workoutId }
}

/// Reachable from an exercise's "..." menu during an active workout - the
/// full history of reps/weights logged for this exercise, and any notes
/// left along the way (e.g. "shoulder very sore on this one"), across
/// every past session. Unlike the inline "Last time: ..." context shown
/// while training (last workout only), this is the complete progress view.
struct ExerciseHistoryView: View {
    let exercise: Exercise

    @State private var entries: [ExerciseHistoryEntry] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    private let workoutRepository = WorkoutRepository()
    private let noteRepository = ExerciseNoteRepository()

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            } else if entries.isEmpty {
                if !isLoading {
                    Text("No history logged yet for \(exercise.name).")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(entries) { entry in
                    Section {
                        if entry.sets.isEmpty {
                            Text("No sets logged.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(entry.sets) { set in
                                HStack {
                                    Text("\(set.reps) reps")
                                    Spacer()
                                    Text("\(set.weightKg.formatted(.number.precision(.fractionLength(0...2)))) kg")
                                    if let rpe = set.rpe {
                                        Text("RPE \(String(format: "%.1f", rpe))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        if let note = entry.note {
                            Label(note, systemImage: "text.bubble")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text(entry.performedAt, style: .date)
                    }
                }
            }
        }
        .navigationTitle(exercise.name)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let sets = try await workoutRepository.allSets(exerciseId: exercise.id)
            let notes = (try? await noteRepository.fetchNotes(exerciseId: exercise.id)) ?? []

            let allWorkoutIds = Array(Set(sets.map(\.workoutId)).union(notes.map(\.workoutId)))
            let workouts = try await workoutRepository.fetchWorkouts(ids: allWorkoutIds)
            let workoutsById = Dictionary(uniqueKeysWithValues: workouts.map { ($0.id, $0) })
            let setsByWorkout = Dictionary(grouping: sets, by: \.workoutId)
            let notesByWorkout = Dictionary(uniqueKeysWithValues: notes.map { ($0.workoutId, $0.note) })

            entries = allWorkoutIds.compactMap { workoutId -> ExerciseHistoryEntry? in
                guard let workout = workoutsById[workoutId] else { return nil }
                // Heaviest set first - what a session actually achieved
                // matters more here than the order it happened in, unlike
                // the live workout grid (which stays in `setIndex` order).
                let workoutSets = (setsByWorkout[workoutId] ?? []).sorted { $0.weightKg > $1.weightKg }
                return ExerciseHistoryEntry(
                    workoutId: workoutId,
                    performedAt: workout.performedAt,
                    sets: workoutSets,
                    note: notesByWorkout[workoutId]
                )
            }.sorted { $0.performedAt > $1.performedAt }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
