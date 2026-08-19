import SwiftUI

struct StartWorkoutView: View {
    @State private var routine: Routine?
    @State private var nextDay: RoutineDay?
    @State private var days: [RoutineDay] = []
    @State private var errorMessage: String?
    @State private var startedWorkout: Workout?
    @State private var isStarting = false
    @State private var exercises: [Exercise] = []
    @State private var exercisesError: String?
    @ObservedObject private var cardioMonitor = CardioSessionMonitor.shared
    private let routineRepository = RoutineRepository()
    private let workoutRepository = WorkoutRepository()
    private let exerciseRepository = ExerciseRepository()

    var body: some View {
        NavigationStack {
            ScrollView {
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
                        Text("Start Today's Workout")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let nextDay {
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
                                Text("Start Today's Workout")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(nextDay == nil || isStarting)

                        if !days.isEmpty {
                            Divider()

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Your Split")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                ForEach(days) { day in
                                    NavigationLink {
                                        RoutineDayDetailView(day: day)
                                    } label: {
                                        HStack {
                                            Text(day.label)
                                            Spacer()
                                            if nextDay?.id == day.id {
                                                Text("Next")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        NavigationLink("Edit My Split") {
                            RoutineEditorView()
                        }
                        .font(.footnote)
                    }

                    if let exercisesError {
                        Text(exercisesError).foregroundStyle(.red)
                    } else if !exercises.isEmpty {
                        DashboardCard(title: "Exercise Progress") {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(exercises) { exercise in
                                    NavigationLink(exercise.name) {
                                        ExerciseProgressionView(exercise: exercise)
                                    }
                                }
                            }
                        }
                    }

                    DashboardCard(title: "Cardio") {
                        VStack(alignment: .leading, spacing: 12) {
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
                            NavigationLink("Cardio History") {
                                CardioHistoryView()
                            }
                            .font(.footnote)
                        }
                    }

                    Divider()

                    WorkoutHistoryView()
                }
                .padding()
            }
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
                days = try await routineRepository.fetchDays(routineId: activeRoutine.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        do {
            exercises = try await exerciseRepository.fetchAll()
        } catch {
            exercisesError = error.localizedDescription
        }
        await CardioSessionMonitor.shared.refresh()
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
