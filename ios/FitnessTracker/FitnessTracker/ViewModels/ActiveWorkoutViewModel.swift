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
    /// The most recent note left on this exercise in a *past* workout (not
    /// this one) - surfaced as a reminder when the exercise comes up again,
    /// e.g. "shoulder was sore on this one" showing up right when it's
    /// relevant instead of only living in `ExerciseHistoryView`.
    var lastNote: ExerciseNote?
    /// One entry per not-yet-confirmed row currently shown, in display order.
    /// Confirming a row always consumes `pendingRows.first` - rows confirm
    /// in order, same as before this became an array instead of a count.
    var pendingRows: [PendingSetKind]

    var id: UUID { exercise.id }

    var suggestion: ProgressionSuggestion? {
        guard let target else { return nil }
        return ProgressionCalculator.suggest(previousSets: previousSets, target: target)
    }

    /// Flags when last session fell short of the day's planned set count
    /// (cut short by time, fatigue, equipment - whatever) - a nudge to
    /// actually hit all of them this time, distinct from `suggestion`'s
    /// weight/rep guidance. Counts only normal sets, same as
    /// `restoreExistingSets` already does elsewhere - a drop set is extra,
    /// not one of the planned working sets.
    var incompleteSetsNote: String? {
        guard let target, !previousSets.isEmpty else { return nil }
        let previousNormalSets = previousSets.filter { !$0.isDropSet }.count
        guard previousNormalSets > 0, previousNormalSets < target.targetSets else { return nil }
        return "Last time you only did \(previousNormalSets) of \(target.targetSets) sets."
    }

    init(exercise: Exercise, target: RoutineDayExercise?) {
        self.exercise = exercise
        self.target = target
        self.pendingRows = Array(repeating: .normal, count: target?.targetSets ?? 3)
    }
}

/// A one-off change to a planned day, made before starting it: planned
/// exercises to leave out and extra ones to add. Applies to this workout only -
/// the routine itself isn't touched.
struct WorkoutModification {
    var removedExerciseIds: Set<UUID> = []
    var addedExercises: [Exercise] = []

    var isEmpty: Bool { removedExerciseIds.isEmpty && addedExercises.isEmpty }
}

@MainActor
final class ActiveWorkoutViewModel: ObservableObject {
    @Published private(set) var workout: Workout
    @Published var activeExercises: [ActiveExercise] = [] {
        didSet { scheduleLiveActivityUpdate() }
    }
    @Published var errorMessage: String?
    @Published var isFinished = false
    @Published var isCancelled = false
    @Published var restTimerEndDate: Date? {
        didSet { scheduleLiveActivityUpdate() }
    }
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
    private let exerciseNoteRepository = ExerciseNoteRepository()

    private var lastLoggedExerciseId: UUID?
    private var liveActivityTask: Task<Void, Never>?
    private var liveActivityEnded = false

    /// Applied once, after the day's exercises first load (never on a resume).
    private var pendingModification: WorkoutModification?

    init(workout: Workout, modification: WorkoutModification? = nil) {
        self.workout = workout
        self.pendingModification = (modification?.isEmpty ?? true) ? nil : modification
    }

    /// Pushes the current exercise / set / rest timer to the Live Activity.
    /// `activeExercises` changes many times in a row while a workout loads, so
    /// updates are coalesced into one shortly after the last change.
    private func scheduleLiveActivityUpdate() {
        guard !liveActivityEnded, !activeExercises.isEmpty else { return }
        liveActivityTask?.cancel()
        liveActivityTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled, let self, !self.liveActivityEnded else { return }
            let entries = self.activeExercises.map { active in
                WorkoutLiveActivityPlan.Entry(
                    name: active.exercise.name,
                    loggedSets: active.loggedSets.filter { !$0.isDropSet }.count,
                    pendingSets: active.pendingRows.filter { $0 == .normal }.count,
                    lastSet: active.loggedSets.last.map {
                        WorkoutLiveActivityPlan.setText(name: active.exercise.name, weightKg: $0.weightKg, reps: $0.reps)
                    }
                )
            }
            // Resuming has no memory of what was logged last, so fall back to
            // the last exercise in order that has any sets.
            let lastIndex = self.activeExercises.firstIndex { $0.id == self.lastLoggedExerciseId }
                ?? self.activeExercises.lastIndex { !$0.loggedSets.isEmpty }
            let state = WorkoutLiveActivityPlan.state(entries: entries, lastLoggedIndex: lastIndex, restEndsAt: self.restTimerEndDate)
            await WorkoutLiveActivityManager.shared.sync(workout: self.workout, state: state)
        }
    }

    private func endLiveActivity() {
        liveActivityEnded = true
        liveActivityTask?.cancel()
        Task { await WorkoutLiveActivityManager.shared.end() }
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
                active.previousSets = (try? await workoutRepository.previousSets(exerciseId: exercise.id, gymId: workout.gymId)) ?? []
                // The most recent note from a *previous* workout - never
                // this one, so reopening a session you've already left a
                // note in this session doesn't show it back as if it were
                // old context.
                active.lastNote = (try? await exerciseNoteRepository.fetchNotes(exerciseId: exercise.id))?
                    .first { $0.workoutId != workout.id }
                restoreExistingSets(existingSetsByExercise[workoutExercise.exerciseId] ?? [], into: &active)
                activeExercises.append(active)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        // The "Start Modified Workout" changes - leave out some planned
        // exercises, add others - through the same paths as doing it mid-workout.
        if let modification = pendingModification {
            pendingModification = nil
            for exerciseId in modification.removedExerciseIds {
                await removeExercise(exerciseId: exerciseId)
            }
            for exercise in modification.addedExercises {
                await addAdHocExercise(exercise)
            }
            // Removing and adding leaves gaps and repeats in the saved
            // positions; renumber them to match what's on screen.
            await persistExerciseOrder()
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
        active.previousSets = (try? await workoutRepository.previousSets(exerciseId: exercise.id, gymId: workout.gymId)) ?? []
        active.lastNote = (try? await exerciseNoteRepository.fetchNotes(exerciseId: exercise.id))?
            .first { $0.workoutId != workout.id }
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

    /// Swaps one exercise for another at the same spot in this workout only
    /// - the routine day's own template is untouched, so next time this day
    /// comes up it's back to normal. Any sets already logged against the
    /// old exercise are dropped along with it (they're not valid history for
    /// whatever replaces it), same as `removeExercise`; the new exercise
    /// starts ad hoc, with no day-template target of its own, same as
    /// `addAdHocExercise` - a swapped-in exercise wasn't part of today's
    /// plan.
    func replaceExercise(oldExerciseId: UUID, with newExercise: Exercise) async {
        guard let index = activeExercises.firstIndex(where: { $0.id == oldExerciseId }) else { return }
        // The DB's (workout_id, exercise_id) uniqueness means swapping in an
        // exercise already elsewhere in this workout (e.g. a superset
        // partner) would collide - same guard `addAdHocExercise` already
        // uses for the plain "add" case.
        guard !activeExercises.contains(where: { $0.id == newExercise.id }) else { return }
        do {
            try await offlineQueue.deleteSets(workout: workout, exerciseId: oldExerciseId)
            try await offlineQueue.removeWorkoutExercise(workout: workout, exerciseId: oldExerciseId)
            try await offlineQueue.addWorkoutExercise(workout: workout, exerciseId: newExercise.id, position: index)
            var replacement = ActiveExercise(exercise: newExercise, target: nil)
            replacement.previousSets = (try? await workoutRepository.previousSets(exerciseId: newExercise.id, gymId: workout.gymId)) ?? []
            replacement.lastNote = (try? await exerciseNoteRepository.fetchNotes(exerciseId: newExercise.id))?
                .first { $0.workoutId != workout.id }
            activeExercises[index] = replacement
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
            lastLoggedExerciseId = exerciseId
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

    /// Changes which gym this specific workout is logged against (e.g. the
    /// preferred default was wrong for a one-off session elsewhere) -
    /// doesn't touch the preference itself, just this session.
    func setGym(_ gymId: UUID?) async {
        do {
            try await offlineQueue.setGym(workout: workout, gymId: gymId)
            workout = Workout(
                id: workout.id,
                routineDayId: workout.routineDayId,
                performedAt: workout.performedAt,
                startedAt: workout.startedAt,
                endedAt: workout.endedAt,
                name: workout.name,
                notes: workout.notes,
                rating: workout.rating,
                gymId: gymId,
                avgHeartRate: workout.avgHeartRate,
                activeCalories: workout.activeCalories,
                healthkitWorkoutUUID: workout.healthkitWorkoutUUID
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func finish(rating: Int, notes: String) async {
        do {
            try? await offlineQueue.updateNotes(workout: workout, notes: notes)
            try await offlineQueue.finishWorkout(workout: workout, rating: rating)
            endLiveActivity()
            isFinished = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancel() async {
        do {
            try await offlineQueue.deleteWorkout(workoutId: workout.id)
            endLiveActivity()
            isCancelled = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
