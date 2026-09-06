import Combine
import Foundation

enum PendingSetKind {
    case normal, drop
}

struct ActiveExercise: Identifiable {
    let exercise: Exercise
    let target: RoutineDayExercise?
    var previousSets: [WorkoutSet] = []
    var loggedSets: [WorkoutSet] = []
    /// One entry per not-yet-confirmed row currently shown, in display order.
    /// Confirming a row always consumes `pendingRows.first` - rows confirm
    /// in order, same as before this became an array instead of a count.
    var pendingRows: [PendingSetKind]

    var id: UUID { exercise.id }

    var suggestion: ProgressionSuggestion? {
        guard let target else { return nil }
        return ProgressionCalculator.suggest(previousSets: previousSets, target: target)
    }

    init(exercise: Exercise, target: RoutineDayExercise?) {
        self.exercise = exercise
        self.target = target
        self.pendingRows = Array(repeating: .normal, count: target?.targetSets ?? 3)
    }
}

@MainActor
final class ActiveWorkoutViewModel: ObservableObject {
    @Published private(set) var workout: Workout
    @Published var activeExercises: [ActiveExercise] = []
    @Published var notes: String
    @Published var errorMessage: String?
    @Published var isFinished = false
    @Published var isCancelled = false
    @Published var restTimerEndDate: Date?
    /// Muscle groups with a currently-unresolved injury - lets the view warn
    /// on any exercise whose `primaryMuscleGroup` matches, without the view
    /// itself needing to know about injuries at all.
    @Published var activeInjuryMuscleGroups: Set<String> = []

    let restDurationSeconds: TimeInterval = 120

    private let routineRepository = RoutineRepository()
    private let workoutRepository = WorkoutRepository()
    private let offlineQueue = OfflineWorkoutQueue.shared
    private let exerciseRepository = ExerciseRepository()
    private let injuryRepository = InjuryRepository()
    private var notesSaveTask: Task<Void, Never>?

    init(workout: Workout) {
        self.workout = workout
        self.notes = workout.notes ?? ""
    }

    func loadTemplate() async {
        guard activeExercises.isEmpty else { return }
        do {
            // Resuming a workout that already has sets logged (backgrounded
            // mid-session, or reopened after the app was killed) needs those
            // sets restored into view, not just re-loaded from the day
            // template as if starting fresh. Always local (`OfflineWorkoutQueue`
            // is the source of truth for an active workout's own sets
            // regardless of connectivity), so this never fails offline.
            let existingSets = try await offlineQueue.fetchSets(workoutId: workout.id)
            let existingSetsByExercise = Dictionary(grouping: existingSets, by: \.exerciseId)

            // The exercise library and today's routine-day exercises are
            // reference data, not something this queue owns - fall back to
            // the last successful fetch when offline rather than failing
            // outright, so a workout opened at the gym with no signal still
            // renders as long as it's been loaded at least once before.
            let allExercises: [Exercise]
            if let fetched = try? await exerciseRepository.fetchAll() {
                allExercises = fetched
                OfflineReferenceCache.save(fetched, key: "exercise-library")
            } else {
                allExercises = OfflineReferenceCache.load([Exercise].self, key: "exercise-library") ?? []
            }
            let byId = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.id, $0) })

            var templateExerciseIds: Set<UUID> = []
            if let routineDayId = workout.routineDayId {
                let dayExercisesCacheKey = "routine-day-exercises-\(routineDayId.uuidString)"
                let dayExercises: [RoutineDayExercise]
                if let fetched = try? await routineRepository.fetchDayExercises(routineDayId: routineDayId) {
                    dayExercises = fetched
                    OfflineReferenceCache.save(fetched, key: dayExercisesCacheKey)
                } else {
                    dayExercises = OfflineReferenceCache.load([RoutineDayExercise].self, key: dayExercisesCacheKey) ?? []
                }
                for dayExercise in dayExercises {
                    guard let exercise = byId[dayExercise.exerciseId] else { continue }
                    templateExerciseIds.insert(exercise.id)
                    var active = ActiveExercise(exercise: exercise, target: dayExercise)
                    active.previousSets = (try? await workoutRepository.previousSets(exerciseId: exercise.id)) ?? []
                    restoreExistingSets(existingSetsByExercise[exercise.id] ?? [], into: &active)
                    activeExercises.append(active)
                }
            }

            // A resumed workout may also have sets logged against an
            // exercise added ad hoc mid-session (not part of the day's
            // template) - without this, those rows would silently vanish
            // from view even though the sets themselves are safely saved.
            for (exerciseId, sets) in existingSetsByExercise where !templateExerciseIds.contains(exerciseId) {
                guard let exercise = byId[exerciseId] else { continue }
                var active = ActiveExercise(exercise: exercise, target: nil)
                active.previousSets = (try? await workoutRepository.previousSets(exerciseId: exercise.id)) ?? []
                restoreExistingSets(sets, into: &active)
                activeExercises.append(active)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        // Advisory only - never blocks the workout from loading if this
        // fails (offline, or any other error).
        activeInjuryMuscleGroups = (try? await injuryRepository.fetchActiveMuscleGroups()) ?? []
    }

    /// Marks a resumed exercise's already-logged sets as confirmed and
    /// shrinks the remaining pending rows to match - drop sets are extra,
    /// chained sets and don't count against the target, so only normal
    /// sets reduce it.
    private func restoreExistingSets(_ sets: [WorkoutSet], into active: inout ActiveExercise) {
        guard !sets.isEmpty else { return }
        active.loggedSets = sets.sorted { $0.setIndex < $1.setIndex }
        let loggedNormalCount = active.loggedSets.filter { !$0.isDropSet }.count
        let remainingTarget = max(0, active.pendingRows.count - loggedNormalCount)
        active.pendingRows = Array(repeating: .normal, count: remainingTarget)
    }

    func addAdHocExercise(_ exercise: Exercise) async {
        guard !activeExercises.contains(where: { $0.id == exercise.id }) else { return }
        var active = ActiveExercise(exercise: exercise, target: nil)
        active.previousSets = (try? await workoutRepository.previousSets(exerciseId: exercise.id)) ?? []
        activeExercises.append(active)
    }

    func removeExercise(exerciseId: UUID) async {
        guard let index = activeExercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        activeExercises.remove(at: index)
        do {
            try await offlineQueue.deleteSets(workoutId: workout.id, exerciseId: exerciseId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logSet(for exerciseId: UUID, reps: Int, weightKg: Double, rpe: Double?, isDropSet: Bool) async {
        guard let index = activeExercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        let nextSetIndex = activeExercises[index].loggedSets.count + 1
        do {
            let set = try await offlineQueue.addSet(
                workoutId: workout.id,
                exerciseId: exerciseId,
                setIndex: nextSetIndex,
                reps: reps,
                weightKg: weightKg,
                rpe: rpe,
                isWarmup: false,
                isDropSet: isDropSet
            )
            activeExercises[index].loggedSets.append(set)
            if !activeExercises[index].pendingRows.isEmpty {
                activeExercises[index].pendingRows.removeFirst()
            }

            // Drops chain immediately with no rest between them by definition.
            if isDropSet {
                skipRestTimer()
            } else {
                restTimerEndDate = Date().addingTimeInterval(restDurationSeconds)
                RestTimerNotifier.requestAuthorizationIfNeeded()
                RestTimerNotifier.scheduleRestComplete(after: restDurationSeconds)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func skipRestTimer() {
        restTimerEndDate = nil
        RestTimerNotifier.cancelPending()
    }

    /// Undoes an accidental tick: deletes the logged set and turns its row
    /// back into an editable one. Only ever the most recently confirmed set
    /// for an exercise - the UI only offers this on the last row, since
    /// removing one from the middle would misalign every later row's
    /// positional display.
    func unlogSet(for exerciseId: UUID, set: WorkoutSet) async {
        guard let index = activeExercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        guard activeExercises[index].loggedSets.last?.id == set.id else { return }
        do {
            try await offlineQueue.deleteSet(setId: set.id)
            activeExercises[index].loggedSets.removeLast()
            activeExercises[index].pendingRows.insert(set.isDropSet ? .drop : .normal, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addExtraSetRow(for exerciseId: UUID) {
        guard let index = activeExercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        activeExercises[index].pendingRows.append(.normal)
    }

    func addDropSetRow(for exerciseId: UUID) {
        guard let index = activeExercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        activeExercises[index].pendingRows.append(.drop)
    }

    /// Removes one specific unconfirmed row (e.g. an accidental "Add Set" or
    /// "Add Drop" tap, swiped away).
    func removeSetRow(for exerciseId: UUID, at pendingIndex: Int) {
        guard let index = activeExercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        guard activeExercises[index].pendingRows.indices.contains(pendingIndex) else { return }
        activeExercises[index].pendingRows.remove(at: pendingIndex)
    }

    func saveNotes(_ text: String) {
        notes = text
        notesSaveTask?.cancel()
        let workoutId = workout.id
        notesSaveTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            try? await offlineQueue.updateNotes(workoutId: workoutId, notes: text)
        }
    }

    func finish(rating: Int?) async {
        do {
            try await offlineQueue.finishWorkout(workoutId: workout.id, rating: rating)
            isFinished = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancel() async {
        do {
            try await offlineQueue.deleteWorkout(workoutId: workout.id)
            isCancelled = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
