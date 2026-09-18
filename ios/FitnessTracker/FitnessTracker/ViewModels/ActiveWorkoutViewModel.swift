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

    init(workout: Workout) {
        self.workout = workout
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

            var dayExercisesById: [UUID: RoutineDayExercise] = [:]
            var templateOrder: [UUID] = []
            if let routineDayId = workout.routineDayId {
                let dayExercisesCacheKey = "routine-day-exercises-\(routineDayId.uuidString)"
                let dayExercises: [RoutineDayExercise]
                if let fetched = try? await routineRepository.fetchDayExercises(routineDayId: routineDayId) {
                    dayExercises = fetched
                    OfflineReferenceCache.save(fetched, key: dayExercisesCacheKey)
                } else {
                    dayExercises = OfflineReferenceCache.load([RoutineDayExercise].self, key: dayExercisesCacheKey) ?? []
                }
                for dayExercise in dayExercises where byId[dayExercise.exerciseId] != nil {
                    dayExercisesById[dayExercise.exerciseId] = dayExercise
                    templateOrder.append(dayExercise.exerciseId)
                }
            }

            // This workout's own persisted exercise list - the source of
            // truth for which exercises are actually part of it and in what
            // order, once it exists (see `WorkoutExercise`'s doc comment).
            var workoutExercises = try await offlineQueue.fetchWorkoutExercises(workoutId: workout.id)

            // Nothing persisted yet - either a brand new workout, or one
            // started before this table existed. Seed it once, in template
            // order, plus any exercise that already has sets logged but
            // isn't part of today's template (an ad hoc exercise from an
            // old workout predating this table) - and persist that seed so
            // every later load, reorder, or removal reads from here instead
            // of re-deriving from the template, which remembers neither.
            if workoutExercises.isEmpty {
                var seedOrder = templateOrder
                for exerciseId in existingSetsByExercise.keys where dayExercisesById[exerciseId] == nil {
                    seedOrder.append(exerciseId)
                }
                for (index, exerciseId) in seedOrder.enumerated() where byId[exerciseId] != nil {
                    if let saved = try? await offlineQueue.addWorkoutExercise(workout: workout, exerciseId: exerciseId, position: index) {
                        workoutExercises.append(saved)
                    }
                }
            }

            for workoutExercise in workoutExercises.sorted(by: { $0.position < $1.position }) {
                guard let exercise = byId[workoutExercise.exerciseId] else { continue }
                var active = ActiveExercise(exercise: exercise, target: dayExercisesById[workoutExercise.exerciseId])
                active.previousSets = (try? await workoutRepository.previousSets(exerciseId: exercise.id)) ?? []
                restoreExistingSets(existingSetsByExercise[workoutExercise.exerciseId] ?? [], into: &active)
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
        do {
            try await offlineQueue.addWorkoutExercise(workout: workout, exerciseId: exercise.id, position: activeExercises.count - 1)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeExercise(exerciseId: UUID) async {
        guard let index = activeExercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        activeExercises.remove(at: index)
        do {
            try await offlineQueue.deleteSets(workout: workout, exerciseId: exerciseId)
            // Distinct from the sets delete above - without this, the
            // exercise is still part of the workout's persisted list and
            // would reappear (with zero sets) the next time this workout
            // is resumed.
            try await offlineQueue.removeWorkoutExercise(workout: workout, exerciseId: exerciseId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Persists a mid-workout reorder - `activeExercises` itself is already
    /// reordered by the view (`.onMove`) before this is called; this just
    /// saves the new order so it survives the workout view being torn down
    /// and rebuilt.
    func persistExerciseOrder() async {
        do {
            try await offlineQueue.reorderWorkoutExercises(workout: workout, orderedExerciseIds: activeExercises.map(\.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logSet(for exerciseId: UUID, reps: Int, weightKg: Double, rpe: Double?, isDropSet: Bool) async {
        guard let index = activeExercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        let nextSetIndex = activeExercises[index].loggedSets.count + 1
        do {
            let set = try await offlineQueue.addSet(
                workout: workout,
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

    func finish(rating: Int, notes: String) async {
        do {
            try? await offlineQueue.updateNotes(workout: workout, notes: notes)
            try await offlineQueue.finishWorkout(workout: workout, rating: rating)
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
