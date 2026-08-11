import SwiftUI

struct StartWorkoutView: View {
    @State private var routine: Routine?
    @State private var nextDay: RoutineDay?
    @State private var errorMessage: String?
    @State private var startedWorkout: Workout?
    @State private var isStarting = false
    private let routineRepository = RoutineRepository()
    private let workoutRepository = WorkoutRepository()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }

                if routine == nil {
                    Text("Set up your split to get started.")
                        .foregroundStyle(.secondary)
                    NavigationLink("Set Up My Split") {
                        RoutineEditorView()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    if let nextDay {
                        Text("Next up")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(nextDay.label)
                            .font(.largeTitle.bold())
                    } else {
                        Text("Add a day to your split first.")
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        Task { await startWorkout() }
                    } label: {
                        if isStarting {
                            ProgressView()
                        } else {
                            Text("Start Workout")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(nextDay == nil || isStarting)

                    NavigationLink("Edit My Split") {
                        RoutineEditorView()
                    }
                    .font(.footnote)
                }
            }
            .padding()
            .navigationTitle("Train")
            .task { await load() }
            .navigationDestination(item: $startedWorkout) { workout in
                ActiveWorkoutView(workout: workout)
            }
        }
    }

    private func load() async {
        do {
            let activeRoutine = try await routineRepository.fetchActiveRoutine()
            routine = activeRoutine
            if let activeRoutine {
                nextDay = try await workoutRepository.nextRoutineDay(routineId: activeRoutine.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startWorkout() async {
        guard let nextDay else { return }
        isStarting = true
        defer { isStarting = false }
        do {
            startedWorkout = try await workoutRepository.startWorkout(routineDayId: nextDay.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
