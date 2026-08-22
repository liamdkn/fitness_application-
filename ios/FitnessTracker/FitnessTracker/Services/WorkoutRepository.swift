import Foundation
import Supabase

struct WorkoutRepository {
    let client = SupabaseService.shared.client

    private struct NewWorkout: Encodable {
        let user_id: UUID
        let routine_day_id: UUID?
    }

    private struct NewWorkoutSet: Encodable {
        let workout_id: UUID
        let user_id: UUID
        let exercise_id: UUID
        let set_index: Int
        let reps: Int
        let weight_kg: Double
        let rpe: Double?
        let is_warmup: Bool
        let is_drop_set: Bool
    }

    private struct EndWorkoutUpdate: Encodable {
        let ended_at: Date
        let rating: Int?
    }

    private struct NotesUpdate: Encodable {
        let notes: String
    }

    private struct RoutineIdParam: Encodable {
        let for_routine_id: UUID
    }

    private struct ExerciseIdParam: Encodable {
        let for_exercise_id: UUID
    }

    // `next_routine_day` returns a single `routine_days` row, not a set. When
    // there's no match, Postgres/PostgREST represents that as a composite of
    // all-null fields (not JSON `null`), so this decodes leniently and maps
    // an all-null result to nil rather than throwing.
    private struct RoutineDayRPCResult: Decodable {
        let id: UUID?
        let routineId: UUID?
        let position: Int?
        let label: String?
        let isOptional: Bool?

        enum CodingKeys: String, CodingKey {
            case id
            case routineId = "routine_id"
            case position, label
            case isOptional = "is_optional"
        }

        var routineDay: RoutineDay? {
            guard let id, let routineId, let position, let label else { return nil }
            return RoutineDay(id: id, routineId: routineId, position: position, label: label, isOptional: isOptional ?? false)
        }
    }

    func nextRoutineDay(routineId: UUID) async throws -> RoutineDay? {
        let result: RoutineDayRPCResult = try await client
            .rpc("next_routine_day", params: RoutineIdParam(for_routine_id: routineId))
            .execute()
            .value
        return result.routineDay
    }

    func previousSets(exerciseId: UUID) async throws -> [WorkoutSet] {
        try await client
            .rpc("previous_exercise_sets", params: ExerciseIdParam(for_exercise_id: exerciseId))
            .execute()
            .value
    }

    func startWorkout(routineDayId: UUID?) async throws -> Workout {
        let userId = try await client.auth.session.user.id
        let inserted: [Workout] = try await client
            .from("workouts")
            .insert(NewWorkout(user_id: userId, routine_day_id: routineDayId))
            .select()
            .execute()
            .value
        guard let workout = inserted.first else {
            throw RepositoryError.insertFailed
        }
        return workout
    }

    func finishWorkout(workoutId: UUID, rating: Int?) async throws {
        try await client
            .from("workouts")
            .update(EndWorkoutUpdate(ended_at: Date(), rating: rating))
            .eq("id", value: workoutId)
            .execute()
    }

    func updateNotes(workoutId: UUID, notes: String) async throws {
        try await client
            .from("workouts")
            .update(NotesUpdate(notes: notes))
            .eq("id", value: workoutId)
            .execute()
    }

    func deleteWorkout(workoutId: UUID) async throws {
        try await client
            .from("workouts")
            .delete()
            .eq("id", value: workoutId)
            .execute()
    }

    func addSet(
        workoutId: UUID,
        exerciseId: UUID,
        setIndex: Int,
        reps: Int,
        weightKg: Double,
        rpe: Double?,
        isWarmup: Bool,
        isDropSet: Bool = false
    ) async throws -> WorkoutSet {
        let userId = try await client.auth.session.user.id
        let inserted: [WorkoutSet] = try await client
            .from("workout_sets")
            .insert(NewWorkoutSet(
                workout_id: workoutId,
                user_id: userId,
                exercise_id: exerciseId,
                set_index: setIndex,
                reps: reps,
                weight_kg: weightKg,
                rpe: rpe,
                is_warmup: isWarmup,
                is_drop_set: isDropSet
            ))
            .select()
            .execute()
            .value
        guard let set = inserted.first else {
            throw RepositoryError.insertFailed
        }
        return set
    }

    func deleteSet(setId: UUID) async throws {
        try await client
            .from("workout_sets")
            .delete()
            .eq("id", value: setId)
            .execute()
    }

    func deleteSets(workoutId: UUID, exerciseId: UUID) async throws {
        try await client
            .from("workout_sets")
            .delete()
            .eq("workout_id", value: workoutId)
            .eq("exercise_id", value: exerciseId)
            .execute()
    }

    func fetchSets(workoutId: UUID) async throws -> [WorkoutSet] {
        try await client
            .from("workout_sets")
            .select()
            .eq("workout_id", value: workoutId)
            .order("set_index")
            .execute()
            .value
    }

    /// The most recent unfinished workout, if any - lets the Train tab
    /// offer a "Resume Workout" path instead of leaving an in-progress
    /// session stranded whenever the app relaunches cold (e.g. iOS
    /// terminating it in the background mid-workout) rather than just
    /// resuming an already-running process.
    func fetchActive() async throws -> Workout? {
        let workouts: [Workout] = try await client
            .from("workouts")
            .select()
            .is("ended_at", value: nil)
            .order("started_at", ascending: false)
            .limit(1)
            .execute()
            .value
        return workouts.first
    }

    func fetchHistory(limit: Int = 50) async throws -> [Workout] {
        try await client
            .from("workouts")
            .select()
            .order("performed_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    /// All workouts performed within an inclusive range - used by the
    /// weekly adherence score to tell which calendar days had a session.
    func fetchWorkouts(from: Date, to: Date) async throws -> [Workout] {
        try await client
            .from("workouts")
            .select()
            .gte("performed_at", value: from.ISO8601Format())
            .lte("performed_at", value: to.ISO8601Format())
            .order("performed_at")
            .execute()
            .value
    }

    /// Per-workout progression points for a single exercise (est. 1RM, max
    /// weight, volume), oldest first - the raw series for a progression
    /// chart.
    func fetchProgression(exerciseId: UUID, limit: Int = 30) async throws -> [ExerciseProgressionPoint] {
        let points: [ExerciseProgressionPoint] = try await client
            .from("v_exercise_progression")
            .select()
            .eq("exercise_id", value: exerciseId)
            .order("performed_at", ascending: false)
            .limit(limit)
            .execute()
            .value
        return points.sorted { $0.performedAt < $1.performedAt }
    }

    private struct WorkoutIdRow: Decodable {
        let id: UUID
    }

    /// Whether any workout was performed on the given calendar day - used
    /// by the daily adherence score, which only needs a hit/miss rather
    /// than the full workout record.
    func hasWorkout(on date: Date) async throws -> Bool {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let startOfNextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return false }
        let rows: [WorkoutIdRow] = try await client
            .from("workouts")
            .select("id")
            .gte("performed_at", value: startOfDay.ISO8601Format())
            .lt("performed_at", value: startOfNextDay.ISO8601Format())
            .limit(1)
            .execute()
            .value
        return !rows.isEmpty
    }

    func fetchWeeklyVolumeKg() async throws -> Double {
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        let points: [ExerciseProgressionPoint] = try await client
            .from("v_exercise_progression")
            .select()
            .gte("performed_at", value: startOfWeek.ISO8601Format())
            .execute()
            .value
        return points.reduce(0) { $0 + $1.totalVolumeKg }
    }
}
