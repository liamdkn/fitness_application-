import Foundation
import SwiftData

/// Local-first write path for an active workout, so logging at the gym (no
/// wifi, weak signal) never has to wait on or fail from a network call.
/// Every mutation lands in the local SwiftData store first - fast, durable,
/// and can't fail for a connectivity reason - then a sync to Supabase is
/// attempted in the background: immediately after the write, and again
/// whenever `NetworkMonitor` reports the connection coming back. A
/// client-generated id is reused for both the local row and its eventual
/// Supabase row, which is what makes replaying a sync after a partial
/// failure (e.g. the app was killed mid-flush) safe - syncing the same row
/// twice just upserts it twice, it never creates a duplicate.
///
/// Scope: this only covers the active-workout write surface (start a
/// workout, log/unlog sets, remove an exercise, notes, finish/cancel) plus
/// the reads that surface needs (the resume banner, restoring already-
/// logged sets on reopen). Historical browsing - workout history, weekly
/// training volume, insights - still reads straight from Supabase via
/// `WorkoutRepository` and won't show a workout until it's actually synced.
/// That's an intentional boundary, not an oversight: those screens aren't
/// what's in front of you mid-set at the gym, and everything they'd show
/// becomes correct on its own the moment connectivity returns and this
/// queue flushes.
@MainActor
final class OfflineWorkoutQueue {
    static let shared = OfflineWorkoutQueue()

    private let workoutRepository: WorkoutRepository
    private let networkMonitor: NetworkMonitor
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    /// Guards against two flushes running at once - one kicked off right
    /// after a local write, another from a reconnect callback landing at
    /// nearly the same moment.
    private var isFlushing = false
    /// Set whenever a flush is skipped because one was already running, or
    /// whenever a write happens while a flush is in flight - makes sure
    /// that write's data still gets pushed by one more pass rather than
    /// silently waiting for the next unrelated trigger.
    private var flushAgainRequested = false

    private let pruneAfter: TimeInterval = 60 * 60 * 24 * 2 // 2 days
    /// Belt-and-suspenders alongside the reconnect callback - confirmed on
    /// a real device this is normally redundant (NWPathMonitor's callback
    /// fires promptly), but a long-lived process that lives through a hard
    /// network interface toggle (observed in the Simulator specifically -
    /// its URLSession can end up holding stale connections even after
    /// `NWPathMonitor` reports the path as satisfied again) can otherwise
    /// stay stuck until something else happens to trigger a retry. This
    /// makes the queue self-healing regardless of whether the push signal
    /// is reliable in every environment.
    private let periodicRetryInterval: TimeInterval = 20
    private var periodicRetryTask: Task<Void, Never>?

    /// `nil` defaults - see `OfflineMealQueue.init`'s doc comment for why
    /// an actor-isolated default *value* (`WorkoutRepository()`/`.shared`)
    /// has to be resolved in the body instead of the parameter list.
    init(workoutRepository: WorkoutRepository? = nil, networkMonitor: NetworkMonitor? = nil) {
        self.workoutRepository = workoutRepository ?? WorkoutRepository()
        self.networkMonitor = networkMonitor ?? .shared
        do {
            let configuration = ModelConfiguration(
                "workout-queue",
                schema: Schema([QueuedWorkout.self, QueuedWorkoutSet.self, QueuedWorkoutExercise.self]),
                url: URL.applicationSupportDirectory.appending(path: "workout-queue.store")
            )
            container = try ModelContainer(for: QueuedWorkout.self, QueuedWorkoutSet.self, QueuedWorkoutExercise.self, configurations: configuration)
        } catch {
            fatalError("Failed to create offline workout store: \(error)")
        }
        self.networkMonitor.onReconnected { [weak self] in
            self?.scheduleFlush()
        }
        scheduleFlush()
        startPeriodicRetry()
    }

    private func startPeriodicRetry() {
        periodicRetryTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(periodicRetryInterval * 1_000_000_000))
                await self.flushPendingChanges()
            }
        }
    }

    // MARK: - Active workout

    func startWorkout(routineDayId: UUID?, gymId: UUID? = nil) async throws -> Workout {
        let now = Date()
        let local = QueuedWorkout(id: UUID(), routineDayId: routineDayId, gymId: gymId, startedAt: now, performedAt: now, syncState: .pending)
        context.insert(local)
        try context.save()
        scheduleFlush()
        return local.asWorkout()
    }

    /// Changes which gym an already-started workout is logged against -
    /// e.g. correcting the default preferred gym for a one-off session
    /// somewhere else. Only affects this workout, never the preference
    /// itself.
    func setGym(workout: Workout, gymId: UUID?) async throws {
        let localWorkout = try ensureLocalWorkout(matching: workout)
        localWorkout.gymId = gymId
        localWorkout.syncState = .pending
        try context.save()
        scheduleFlush()
    }

    /// The in-progress workout, if any. Checked locally first - this is the
    /// source of truth regardless of connectivity now - falling back to a
    /// Supabase check only when nothing local exists at all, which covers a
    /// workout still active from before this queue existed, or a fresh
    /// reinstall. A remote hit found that way is mirrored locally so every
    /// later lookup (and any edits) goes through the same offline-safe path.
    func fetchActive() async throws -> Workout? {
        if let local = try fetchLocalActiveWorkout() {
            return local.asWorkout()
        }
        guard networkMonitor.isConnected, let remote = try await workoutRepository.fetchActive() else { return nil }
        let mirrored = QueuedWorkout(
            id: remote.id,
            routineDayId: remote.routineDayId,
            gymId: remote.gymId,
            startedAt: remote.startedAt,
            performedAt: remote.performedAt,
            syncState: .synced
        )
        mirrored.notes = remote.notes
        mirrored.rating = remote.rating
        mirrored.endedAt = remote.endedAt
        context.insert(mirrored)
        try context.save()
        return remote
    }

    func fetchSets(workoutId: UUID) async throws -> [WorkoutSet] {
        guard let workout = try fetchLocalWorkout(id: workoutId) else { return [] }
        return workout.sets
            .filter { !$0.pendingDeletion }
            .sorted { $0.setIndex < $1.setIndex }
            .map { $0.asWorkoutSet(workoutId: workoutId) }
    }

    @discardableResult
    func addSet(
        workout: Workout,
        exerciseId: UUID,
        setIndex: Int,
        reps: Int,
        weightKg: Double,
        rpe: Double?,
        isWarmup: Bool,
        isDropSet: Bool
    ) async throws -> WorkoutSet {
        let localWorkout = try ensureLocalWorkout(matching: workout)
        let set = QueuedWorkoutSet(
            id: UUID(),
            exerciseId: exerciseId,
            setIndex: setIndex,
            reps: reps,
            weightKg: weightKg,
            rpe: rpe,
            isWarmup: isWarmup,
            isDropSet: isDropSet,
            syncState: .pending
        )
        set.workout = localWorkout
        context.insert(set)
        try context.save()
        scheduleFlush()
        return set.asWorkoutSet(workoutId: workout.id)
    }

    func deleteSet(setId: UUID) async throws {
        guard let set = try fetchLocalSet(id: setId) else { return }
        removeOrTombstone(set)
        try context.save()
        scheduleFlush()
    }

    func deleteSets(workout: Workout, exerciseId: UUID) async throws {
        let localWorkout = try ensureLocalWorkout(matching: workout)
        for set in localWorkout.sets where set.exerciseId == exerciseId {
            removeOrTombstone(set)
        }
        try context.save()
        scheduleFlush()
    }

    /// This workout's own exercise list, in display order - see
    /// `QueuedWorkoutExercise`. Empty for a workout started before this
    /// table existed (or one that otherwise hasn't been seeded yet); the
    /// caller falls back to the routine day template in that case and
    /// seeds it via `addWorkoutExercise`.
    func fetchWorkoutExercises(workoutId: UUID) async throws -> [WorkoutExercise] {
        guard let workout = try fetchLocalWorkout(id: workoutId) else { return [] }
        return workout.exercises
            .filter { !$0.pendingDeletion }
            .sorted { $0.position < $1.position }
            .map { $0.asWorkoutExercise(workoutId: workoutId) }
    }

    @discardableResult
    func addWorkoutExercise(workout: Workout, exerciseId: UUID, position: Int) async throws -> WorkoutExercise {
        let localWorkout = try ensureLocalWorkout(matching: workout)
        let entry = QueuedWorkoutExercise(id: UUID(), exerciseId: exerciseId, position: position, syncState: .pending)
        entry.workout = localWorkout
        context.insert(entry)
        try context.save()
        scheduleFlush()
        return entry.asWorkoutExercise(workoutId: workout.id)
    }

    /// Removes this exercise from the workout's own list - distinct from
    /// (and always called alongside) `deleteSets`, which only clears its
    /// logged sets. Without this, the exercise would still be part of the
    /// workout's persisted list and reappear (with zero sets) the next
    /// time this workout is resumed.
    func removeWorkoutExercise(workout: Workout, exerciseId: UUID) async throws {
        let localWorkout = try ensureLocalWorkout(matching: workout)
        for entry in localWorkout.exercises where entry.exerciseId == exerciseId {
            removeOrTombstone(entry)
        }
        try context.save()
        scheduleFlush()
    }

    /// Rewrites every entry's `position` to match `orderedExerciseIds` -
    /// simplest correct approach for a full reorder (a handful of rows,
    /// not a hot path), rather than trying to compute a minimal diff.
    func reorderWorkoutExercises(workout: Workout, orderedExerciseIds: [UUID]) async throws {
        let localWorkout = try ensureLocalWorkout(matching: workout)
        let byExerciseId = Dictionary(uniqueKeysWithValues: localWorkout.exercises.filter { !$0.pendingDeletion }.map { ($0.exerciseId, $0) })
        for (index, exerciseId) in orderedExerciseIds.enumerated() {
            guard let entry = byExerciseId[exerciseId], entry.position != index else { continue }
            entry.position = index
            entry.syncState = .pending
        }
        try context.save()
        scheduleFlush()
    }

    func updateNotes(workout: Workout, notes: String) async throws {
        let localWorkout = try ensureLocalWorkout(matching: workout)
        localWorkout.notes = notes
        localWorkout.syncState = .pending
        try context.save()
        scheduleFlush()
    }

    func finishWorkout(workout: Workout, rating: Int?) async throws {
        let localWorkout = try ensureLocalWorkout(matching: workout)
        localWorkout.endedAt = Date()
        localWorkout.rating = rating
        localWorkout.syncState = .pending
        try context.save()
        scheduleFlush()
    }

    func deleteWorkout(workoutId: UUID) async throws {
        guard let workout = try fetchLocalWorkout(id: workoutId) else { return }
        if workout.syncState == .pending {
            // Never made it to the server - nothing to tell it about.
            context.delete(workout)
        } else {
            workout.pendingDeletion = true
        }
        try context.save()
        scheduleFlush()
    }

    // MARK: - Local lookups

    private func removeOrTombstone(_ set: QueuedWorkoutSet) {
        if set.syncState == .pending {
            context.delete(set)
        } else {
            set.pendingDeletion = true
        }
    }

    private func removeOrTombstone(_ entry: QueuedWorkoutExercise) {
        if entry.syncState == .pending {
            context.delete(entry)
        } else {
            entry.pendingDeletion = true
        }
    }

    private func fetchLocalActiveWorkout() throws -> QueuedWorkout? {
        let descriptor = FetchDescriptor<QueuedWorkout>(
            predicate: #Predicate { $0.endedAt == nil && !$0.pendingDeletion }
        )
        return try context.fetch(descriptor).first
    }

    private func fetchLocalWorkout(id: UUID) throws -> QueuedWorkout? {
        var descriptor = FetchDescriptor<QueuedWorkout>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Recreates the local row from `workout` if it's ever gone missing
    /// (e.g. a device/store reset while this workout was still active)
    /// instead of letting every further edit to it fail or silently no-op
    /// - a workout's local mirror should never actually vanish mid-session
    /// given how this queue is supposed to work, but self-healing here
    /// means a real edit (a swapped-out exercise, a logged set) never gets
    /// silently lost to that state ever again if it somehow does. Safe to
    /// call when the row already exists - it's a plain fetch-or-create, and
    /// re-marking an already-synced row `.pending` just costs one harmless
    /// extra upsert on the next flush.
    private func ensureLocalWorkout(matching workout: Workout) throws -> QueuedWorkout {
        if let existing = try fetchLocalWorkout(id: workout.id) {
            return existing
        }
        let recreated = QueuedWorkout(
            id: workout.id,
            routineDayId: workout.routineDayId,
            gymId: workout.gymId,
            startedAt: workout.startedAt,
            performedAt: workout.performedAt,
            syncState: .pending
        )
        recreated.notes = workout.notes
        recreated.rating = workout.rating
        recreated.endedAt = workout.endedAt
        context.insert(recreated)
        try context.save()
        return recreated
    }

    private func fetchLocalSet(id: UUID) throws -> QueuedWorkoutSet? {
        var descriptor = FetchDescriptor<QueuedWorkoutSet>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    // MARK: - Sync

    /// Fire-and-forget - callers never wait on this, so a slow or timed-out
    /// network call while offline can't block the UI. Safe to call after
    /// every single write; `isFlushing` coalesces overlapping calls.
    private func scheduleFlush() {
        Task { await flushPendingChanges() }
    }

    /// Pushes every locally-queued change to Supabase, in order, stopping a
    /// given workout's own sync at its first failure (still offline, or a
    /// genuine error) and moving on to the next workout rather than
    /// aborting the whole pass - one stuck row shouldn't hold back
    /// everything else queued behind it.
    func flushPendingChanges() async {
        guard !isFlushing else {
            flushAgainRequested = true
            return
        }
        isFlushing = true
        defer { isFlushing = false }

        repeat {
            flushAgainRequested = false
            guard networkMonitor.isConnected else { return }

            guard let workouts = try? context.fetch(FetchDescriptor<QueuedWorkout>()) else { return }
            for workout in workouts {
                await flush(workout)
            }
            try? context.save()
        } while flushAgainRequested

        pruneOldSyncedWorkouts()
        try? context.save()
    }

    private func flush(_ workout: QueuedWorkout) async {
        if workout.pendingDeletion {
            do {
                try await workoutRepository.deleteWorkout(workoutId: workout.id)
                context.delete(workout) // cascades to its local sets too.
            } catch {
                // Still offline, or a genuine failure - leave the tombstone
                // in place and retry on the next flush.
            }
            return
        }

        if workout.syncState == .pending {
            do {
                try await workoutRepository.upsertWorkout(
                    id: workout.id,
                    routineDayId: workout.routineDayId,
                    gymId: workout.gymId,
                    startedAt: workout.startedAt,
                    performedAt: workout.performedAt,
                    endedAt: workout.endedAt,
                    notes: workout.notes,
                    rating: workout.rating
                )
                workout.syncState = .synced
            } catch {
                // The parent row didn't make it - its sets can't either
                // (they reference workout_id via a foreign key), so there's
                // no point attempting them yet.
                return
            }
        }

        for set in workout.sets {
            if set.pendingDeletion {
                do {
                    try await workoutRepository.deleteSet(setId: set.id)
                    context.delete(set)
                } catch {
                    continue
                }
            } else if set.syncState == .pending {
                do {
                    try await workoutRepository.upsertSet(
                        id: set.id,
                        workoutId: workout.id,
                        exerciseId: set.exerciseId,
                        setIndex: set.setIndex,
                        reps: set.reps,
                        weightKg: set.weightKg,
                        rpe: set.rpe,
                        isWarmup: set.isWarmup,
                        isDropSet: set.isDropSet
                    )
                    set.syncState = .synced
                } catch {
                    continue
                }
            }
        }

        for entry in workout.exercises {
            if entry.pendingDeletion {
                do {
                    try await workoutRepository.deleteWorkoutExercise(id: entry.id)
                    context.delete(entry)
                } catch {
                    continue
                }
            } else if entry.syncState == .pending {
                do {
                    try await workoutRepository.upsertWorkoutExercise(
                        id: entry.id,
                        workoutId: workout.id,
                        exerciseId: entry.exerciseId,
                        position: entry.position
                    )
                    entry.syncState = .synced
                } catch {
                    continue
                }
            }
        }
    }

    /// Local rows are only needed for offline-safe reads/edits while a
    /// workout is still active or freshly finished - once it's fully
    /// synced and a couple of days old, Supabase is the only copy that
    /// needs to exist, so the local mirror is dropped to keep this store
    /// from growing forever.
    private func pruneOldSyncedWorkouts() {
        guard let workouts = try? context.fetch(FetchDescriptor<QueuedWorkout>()) else { return }
        let cutoff = Date().addingTimeInterval(-pruneAfter)
        for workout in workouts {
            guard workout.syncState == .synced,
                  let endedAt = workout.endedAt,
                  endedAt < cutoff,
                  workout.sets.allSatisfy({ $0.syncState == .synced }),
                  workout.exercises.allSatisfy({ $0.syncState == .synced })
            else { continue }
            context.delete(workout)
        }
    }
}
