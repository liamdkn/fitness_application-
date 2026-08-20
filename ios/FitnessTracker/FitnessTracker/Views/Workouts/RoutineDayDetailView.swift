import SwiftUI

struct RoutineDayDetailView: View {
    let day: RoutineDay

    @State private var dayExercises: [RoutineDayExercise] = []
    @State private var exerciseNames: [UUID: String] = [:]
    @State private var errorMessage: String?
    @State private var startedWorkout: Workout?
    @State private var isStarting = false
    private let routineRepository = RoutineRepository()
    private let exerciseRepository = ExerciseRepository()
    private let workoutRepository = WorkoutRepository()

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
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

            Section {
                Button {
                    Task { await startWorkout() }
                } label: {
                    if isStarting {
                        ProgressView()
                    } else {
                        Text("Start This Workout")
                    }
                }
                .disabled(isStarting)
            }
        }
        .navigationTitle(day.label)
        .task { await load() }
        .navigationDestination(item: $startedWorkout) { workout in
            ActiveWorkoutView(workout: workout)
        }
    }

    private func load() async {
        do {
            dayExercises = try await routineRepository.fetchDayExercises(routineDayId: day.id)
            let allExercises = try await exerciseRepository.fetchAll()
            exerciseNames = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.id, $0.name) })
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startWorkout() async {
        isStarting = true
        defer { isStarting = false }
        do {
            startedWorkout = try await workoutRepository.startWorkout(routineDayId: day.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
