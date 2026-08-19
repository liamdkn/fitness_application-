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
    }

    private struct EndWorkoutUpdate: Encodable {
        let ended_at: Date
        let rating: Int?
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

        enum CodingKeys: String, CodingKey {
            case id
            case routineId = "routine_id"
            case position, label
        }

        var routineDay: RoutineDay? {
            guard let id, let routineId, let position, let label else { return nil }
            return RoutineDay(id: id, routineId: routineId, position: position, label: label)
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
        isWarmup: Bool
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
                is_warmup: isWarmup
            ))
            .select()
            .execute()
            .value
        guard let set = inserted.first else {
            throw RepositoryError.insertFailed
        }
        return set
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

    func fetchHistory(limit: Int = 50) async throws -> [Workout] {
        try await client
            .from("workouts")
            .select()
            .order("performed_at", ascending: false)
            .limit(limit)
            .execute()
            .value
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
