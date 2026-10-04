import SwiftUI

/// A planned day, opened from its card's "..." menu: the exercises in it, with
/// a button to start it. Exercises can be added or removed here for just this
/// session - the button then reads "Start Modified Workout" - without
/// changing the routine itself (that's `RoutineEditorView`). The workout is
/// started through `OfflineWorkoutQueue`, like the card's own Start button, so
/// it works with no signal.
struct RoutineDayDetailView: View {
    let day: RoutineDay

    @State private var dayExercises: [RoutineDayExercise] = []
    @State private var exerciseNames: [UUID: String] = [:]
    @State private var errorMessage: String?
    @State private var routineNotes: String?
    @State private var modification = WorkoutModification()
    @State private var showingAddExercise = false
    @State private var startedWorkout: Workout?
    @State private var hasActiveWorkout = false
    @State private var isStarting = false
    private let routineRepository = RoutineRepository()
    private let exerciseRepository = ExerciseRepository()
    private let offlineQueue = OfflineWorkoutQueue.shared

    private var plannedKept: [RoutineDayExercise] {
        dayExercises.filter { !modification.removedExerciseIds.contains($0.exerciseId) }
    }

    private var plannedRemoved: [RoutineDayExercise] {
        dayExercises.filter { modification.removedExerciseIds.contains($0.exerciseId) }
    }

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(AppColor.error)
                    .listRowBackground(Color.clear)
            }

            if !hasActiveWorkout {
                Section {
                    Button {
                        showingAddExercise = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus")
                    }
                    .buttonStyle(.appSecondary)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
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
                .listRowBackground(AppRowBackground())
            }

            if dayExercises.isEmpty && modification.addedExercises.isEmpty {
                Text("No exercises planned for this day yet - you can still start and add them during your workout.")
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            if !plannedKept.isEmpty {
                Section {
                    ForEach(plannedKept) { dayExercise in
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
                        .swipeActions(edge: .trailing) {
                            if !hasActiveWorkout {
                                Button {
                                    withAnimation { _ = modification.removedExerciseIds.insert(dayExercise.exerciseId) }
                                } label: {
                                    Label("Remove", systemImage: "minus.circle")
                                }
                                .tint(AppColor.warning)
                            }
                        }
                    }
                }
                .listRowBackground(AppRowBackground())
            }

            if !modification.addedExercises.isEmpty {
                Section("Added for this workout") {
                    ForEach(modification.addedExercises) { exercise in
                        Text(exercise.name).font(.headline)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    withAnimation { modification.addedExercises.removeAll { $0.id == exercise.id } }
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                }
                .listRowBackground(AppRowBackground())
            }

            if !plannedRemoved.isEmpty {
                Section("Left out of this workout") {
                    ForEach(plannedRemoved) { dayExercise in
                        HStack {
                            Text(exerciseNames[dayExercise.exerciseId] ?? "Exercise")
                                .strikethrough()
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Put back") {
                                withAnimation { _ = modification.removedExerciseIds.remove(dayExercise.exerciseId) }
                            }
                            .font(.subheadline)
                            .buttonStyle(.borderless)
                        }
                    }
                }
                .listRowBackground(AppRowBackground())
            }
        }
        .appScreen()
        .navigationTitle(day.label)
        // The start button sits at the bottom of the screen, clear of the list.
        .safeAreaInset(edge: .bottom) {
            if !hasActiveWorkout {
                Button {
                    Task { await start() }
                } label: {
                    if isStarting {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text(modification.isEmpty ? "Start Workout" : "Start Modified Workout")
                    }
                }
                .buttonStyle(.appAccent)
                .disabled(isStarting)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showingAddExercise) {
            ExercisePickerView { exercise in
                // Already in the plan (maybe left out) or already added: just make sure it's in.
                if modification.removedExerciseIds.contains(exercise.id) {
                    modification.removedExerciseIds.remove(exercise.id)
                } else if !dayExercises.contains(where: { $0.exerciseId == exercise.id })
                            && !modification.addedExercises.contains(where: { $0.id == exercise.id }) {
                    modification.addedExercises.append(exercise)
                    exerciseNames[exercise.id] = exercise.name
                }
            }
        }
        .navigationDestination(item: $startedWorkout) { workout in
            ActiveWorkoutView(workout: workout, modification: modification)
        }
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
        hasActiveWorkout = ((try? await offlineQueue.fetchActive()) ?? nil) != nil
    }

    private func start() async {
        guard !isStarting, !hasActiveWorkout else { return }
        isStarting = true
        defer { isStarting = false }
        do {
            let gymId = (try? await UserPreferencesRepository().fetch())?.preferredGymId
            startedWorkout = try await offlineQueue.startWorkout(routineDayId: day.id, gymId: gymId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
