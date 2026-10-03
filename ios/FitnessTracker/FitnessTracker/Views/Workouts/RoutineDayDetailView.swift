import SwiftUI

/// The day's exercise "menu" - purely a read-only plan list. Starting the
/// workout itself lives only on the Train tab's day card (`WeekDayCard`'s
/// `actionRow`, via `OfflineWorkoutQueue`), not here - this screen used to
/// have its own separate "Start This Workout" button that bypassed the
/// offline queue entirely (called `WorkoutRepository.startWorkout`
/// directly), which meant a workout started from here wouldn't show up as
/// active if you lost signal mid-gym-session. Removed rather than fixed,
/// since duplicating the entry point was the actual problem.
struct RoutineDayDetailView: View {
    let day: RoutineDay

    @State private var dayExercises: [RoutineDayExercise] = []
    @State private var exerciseNames: [UUID: String] = [:]
    @State private var errorMessage: String?
    @State private var routineNotes: String?
    private let routineRepository = RoutineRepository()
    private let exerciseRepository = ExerciseRepository()

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(AppColor.error)
            }

            if let routineNotes, !routineNotes.isEmpty {
                Section {
                    DisclosureGroup("Read before training") {
                        Text(routineNotes)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            if dayExercises.isEmpty {
                Text("No exercises planned for this day yet - you can still start and add them during your workout.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dayExercises) { dayExercise in
                    NavigationLink {
                        ExerciseProgressionView(
                            exerciseId: dayExercise.exerciseId,
                            exerciseName: exerciseNames[dayExercise.exerciseId] ?? "Exercise"
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(exerciseNames[dayExercise.exerciseId] ?? "Exercise")
                                .font(.headline)
                            Text("\(dayExercise.targetSets) sets \u{00d7} \(dayExercise.repRangeLow)-\(dayExercise.repRangeHigh) reps, +\(dayExercise.weightIncrementKg, specifier: "%.1f")kg")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .appScreen()
        .navigationTitle(day.label)
        .task { await load() }
    }

    private func load() async {
        do {
            routineNotes = try? await routineRepository.fetchRoutine(id: day.routineId).notes
            dayExercises = try await routineRepository.fetchDayExercises(routineDayId: day.id)
            let allExercises = try await exerciseRepository.fetchAll()
            exerciseNames = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.id, $0.name) })
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
