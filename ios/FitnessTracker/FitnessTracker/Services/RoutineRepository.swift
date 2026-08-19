import Foundation
import Supabase

struct RoutineRepository {
    let client = SupabaseService.shared.client

    private struct NewRoutine: Encodable {
        let user_id: UUID
        let name: String
    }

    private struct NewRoutineDay: Encodable {
        let routine_id: UUID
        let user_id: UUID
        let position: Int
        let label: String
    }

    private struct NewRoutineDayExercise: Encodable {
        let routine_day_id: UUID
        let user_id: UUID
        let exercise_id: UUID
        let position: Int
        let target_sets: Int
        let rep_range_low: Int
        let rep_range_high: Int
        let weight_increment_kg: Double
    }

    private struct UpdateRoutineDayExercise: Encodable {
        let target_sets: Int
        let rep_range_low: Int
        let rep_range_high: Int
        let weight_increment_kg: Double
    }

    private struct SupersetUpdate: Encodable {
        let superset_group_id: UUID?
    }

    func fetchActiveRoutine() async throws -> Routine? {
        let routines: [Routine] = try await client
            .from("routines")
            .select()
            .eq("is_active", value: true)
            .limit(1)
            .execute()
            .value
        return routines.first
    }

    func createRoutine(name: String) async throws -> Routine {
        let userId = try await client.auth.session.user.id
        let inserted: [Routine] = try await client
            .from("routines")
            .insert(NewRoutine(user_id: userId, name: name))
            .select()
            .execute()
            .value
        guard let routine = inserted.first else {
            throw RepositoryError.insertFailed
        }
        return routine
    }

    func fetchDay(id: UUID) async throws -> RoutineDay {
        try await client
            .from("routine_days")
            .select()
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    func fetchDays(routineId: UUID) async throws -> [RoutineDay] {
        try await client
            .from("routine_days")
            .select()
            .eq("routine_id", value: routineId)
            .order("position")
            .execute()
            .value
    }

    func addDay(routineId: UUID, label: String, position: Int) async throws -> RoutineDay {
        let userId = try await client.auth.session.user.id
        let inserted: [RoutineDay] = try await client
            .from("routine_days")
            .insert(NewRoutineDay(routine_id: routineId, user_id: userId, position: position, label: label))
            .select()
            .execute()
            .value
        guard let day = inserted.first else {
            throw RepositoryError.insertFailed
        }
        return day
    }

    func removeDay(dayId: UUID) async throws {
        try await client
            .from("routine_days")
            .delete()
            .eq("id", value: dayId)
            .execute()
    }

    func fetchDayExercises(routineDayId: UUID) async throws -> [RoutineDayExercise] {
        try await client
            .from("routine_day_exercises")
            .select()
            .eq("routine_day_id", value: routineDayId)
            .order("position")
            .execute()
            .value
    }

    func addExercise(
        routineDayId: UUID,
        exerciseId: UUID,
        position: Int,
        targetSets: Int,
        repRangeLow: Int,
        repRangeHigh: Int,
        weightIncrementKg: Double
    ) async throws -> RoutineDayExercise {
        let userId = try await client.auth.session.user.id
        let inserted: [RoutineDayExercise] = try await client
            .from("routine_day_exercises")
            .insert(NewRoutineDayExercise(
                routine_day_id: routineDayId,
                user_id: userId,
                exercise_id: exerciseId,
                position: position,
                target_sets: targetSets,
                rep_range_low: repRangeLow,
                rep_range_high: repRangeHigh,
                weight_increment_kg: weightIncrementKg
            ))
            .select()
            .execute()
            .value
        guard let dayExercise = inserted.first else {
            throw RepositoryError.insertFailed
        }
        return dayExercise
    }

    func updateExercise(
        dayExerciseId: UUID,
        targetSets: Int,
        repRangeLow: Int,
        repRangeHigh: Int,
        weightIncrementKg: Double
    ) async throws -> RoutineDayExercise {
        let updated: [RoutineDayExercise] = try await client
            .from("routine_day_exercises")
            .update(UpdateRoutineDayExercise(
                target_sets: targetSets,
                rep_range_low: repRangeLow,
                rep_range_high: repRangeHigh,
                weight_increment_kg: weightIncrementKg
            ))
            .eq("id", value: dayExerciseId)
            .select()
            .execute()
            .value
        guard let dayExercise = updated.first else {
            throw RepositoryError.insertFailed
        }
        return dayExercise
    }

    func pairExercises(dayExerciseIdA: UUID, dayExerciseIdB: UUID) async throws -> (RoutineDayExercise, RoutineDayExercise) {
        let existing: [RoutineDayExercise] = try await client
            .from("routine_day_exercises")
            .select()
            .in("id", values: [dayExerciseIdA, dayExerciseIdB])
            .execute()
            .value
        let groupId = existing.compactMap(\.supersetGroupId).first ?? UUID()

        async let updatedA: [RoutineDayExercise] = client
            .from("routine_day_exercises")
            .update(SupersetUpdate(superset_group_id: groupId))
            .eq("id", value: dayExerciseIdA)
            .select()
            .execute()
            .value
        async let updatedB: [RoutineDayExercise] = client
            .from("routine_day_exercises")
            .update(SupersetUpdate(superset_group_id: groupId))
            .eq("id", value: dayExerciseIdB)
            .select()
            .execute()
            .value

        guard let a = try await updatedA.first, let b = try await updatedB.first else {
            throw RepositoryError.insertFailed
        }
        return (a, b)
    }

    func unpairExercise(dayExerciseId: UUID) async throws -> RoutineDayExercise {
        let updated: [RoutineDayExercise] = try await client
            .from("routine_day_exercises")
            .update(SupersetUpdate(superset_group_id: nil))
            .eq("id", value: dayExerciseId)
            .select()
            .execute()
            .value
        guard let dayExercise = updated.first else {
            throw RepositoryError.insertFailed
        }
        return dayExercise
    }

    func removeExercise(dayExerciseId: UUID) async throws {
        try await client
            .from("routine_day_exercises")
            .delete()
            .eq("id", value: dayExerciseId)
            .execute()
    }
}

enum RepositoryError: Error {
    case insertFailed
}
