import Foundation
import SwiftData

/// Where a locally-queued workout/set stands relative to Supabase.
enum SyncState: Int, Codable {
    /// Created or edited locally; not yet confirmed on the server.
    case pending
    /// Confirmed present on the server with the same id and current field
    /// values as of the last successful sync.
    case synced
}

/// Local mirror of a `workouts` row, plus queue bookkeeping. The gym has no
/// wifi and weak signal, so every write during an active workout lands here
/// FIRST - fast, durable, and can't fail for a connectivity reason - and is
/// pushed to Supabase in the background whenever the network's up (see
/// `OfflineWorkoutQueue`). The id is client-generated and reused as the
/// eventual Supabase row's id, which is what makes replaying a sync after a
/// partial failure (e.g. the app got killed mid-flush) safe: syncing the
/// same row twice just upserts it twice, it never creates a duplicate.
@Model
final class QueuedWorkout {
    @Attribute(.unique) var id: UUID
    var routineDayId: UUID?
    var startedAt: Date
    var performedAt: Date
    var endedAt: Date?
    var notes: String?
    var rating: Int?
    var syncState: SyncState
    /// Set when the workout is cancelled - removed from Supabase on the
    /// next successful sync, then purged locally. A row that was never
    /// synced in the first place is deleted immediately instead (nothing
    /// to tell the server about), so this only ever applies to a workout
    /// that had already made it to the server.
    var pendingDeletion: Bool

    @Relationship(deleteRule: .cascade, inverse: \QueuedWorkoutSet.workout)
    var sets: [QueuedWorkoutSet] = []

    @Relationship(deleteRule: .cascade, inverse: \QueuedWorkoutExercise.workout)
    var exercises: [QueuedWorkoutExercise] = []

    init(id: UUID, routineDayId: UUID?, startedAt: Date, performedAt: Date, syncState: SyncState) {
        self.id = id
        self.routineDayId = routineDayId
        self.startedAt = startedAt
        self.performedAt = performedAt
        self.endedAt = nil
        self.notes = nil
        self.rating = nil
        self.syncState = syncState
        self.pendingDeletion = false
    }
}

/// Local mirror of a `workout_sets` row - see `QueuedWorkout`.
@Model
final class QueuedWorkoutSet {
    @Attribute(.unique) var id: UUID
    var workout: QueuedWorkout?
    var exerciseId: UUID
    var setIndex: Int
    var reps: Int
    var weightKg: Double
    var rpe: Double?
    var isWarmup: Bool
    var isDropSet: Bool
    var syncState: SyncState
    var pendingDeletion: Bool

    init(
        id: UUID,
        exerciseId: UUID,
        setIndex: Int,
        reps: Int,
        weightKg: Double,
        rpe: Double?,
        isWarmup: Bool,
        isDropSet: Bool,
        syncState: SyncState
    ) {
        self.id = id
        self.exerciseId = exerciseId
        self.setIndex = setIndex
        self.reps = reps
        self.weightKg = weightKg
        self.rpe = rpe
        self.isWarmup = isWarmup
        self.isDropSet = isDropSet
        self.syncState = syncState
        self.pendingDeletion = false
    }
}

/// Local mirror of a `workout_exercises` row - see `QueuedWorkout`.
@Model
final class QueuedWorkoutExercise {
    @Attribute(.unique) var id: UUID
    var workout: QueuedWorkout?
    var exerciseId: UUID
    var position: Int
    var syncState: SyncState
    var pendingDeletion: Bool

    init(id: UUID, exerciseId: UUID, position: Int, syncState: SyncState) {
        self.id = id
        self.exerciseId = exerciseId
        self.position = position
        self.syncState = syncState
        self.pendingDeletion = false
    }
}

extension QueuedWorkout {
    func asWorkout() -> Workout {
        Workout(
            id: id,
            routineDayId: routineDayId,
            performedAt: performedAt,
            startedAt: startedAt,
            endedAt: endedAt,
            name: nil,
            notes: notes,
            rating: rating
        )
    }
}

extension QueuedWorkoutSet {
    func asWorkoutSet(workoutId: UUID) -> WorkoutSet {
        WorkoutSet(
            id: id,
            workoutId: workoutId,
            exerciseId: exerciseId,
            setIndex: setIndex,
            reps: reps,
            weightKg: weightKg,
            rpe: rpe,
            isWarmup: isWarmup,
            isDropSet: isDropSet
        )
    }
}

extension QueuedWorkoutExercise {
    func asWorkoutExercise(workoutId: UUID) -> WorkoutExercise {
        WorkoutExercise(id: id, workoutId: workoutId, exerciseId: exerciseId, position: position)
    }
}
