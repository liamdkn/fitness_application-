import Foundation
import Supabase

struct ExerciseRepository {
    let client = SupabaseService.shared.client

    private struct NewCustomExercise: Encodable {
        let name: String
        let category: String
        let primary_muscle_group: String?
        let equipment: String?
        let is_custom: Bool
        let created_by: UUID
    }

    func fetchAll() async throws -> [Exercise] {
        try await client
            .from("exercises")
            .select()
            .order("name")
            .execute()
            .value
    }

    /// Ids of exercises the user has logged at least one set for - the ones
    /// with history (see migration 0064).
    func fetchTriedIds() async throws -> Set<UUID> {
        let ids: [UUID] = try await client
            .rpc("tried_exercise_ids")
            .execute()
            .value
        return Set(ids)
    }

    func createCustom(
        name: String,
        category: String,
        primaryMuscleGroup: String?,
        equipment: String?
    ) async throws -> Exercise {
        let userId = try await client.auth.session.user.id
        let inserted: [Exercise] = try await client
            .from("exercises")
            .insert(NewCustomExercise(
                name: name,
                category: category,
                primary_muscle_group: primaryMuscleGroup,
                equipment: equipment,
                is_custom: true,
                created_by: userId
            ))
            .select()
            .execute()
            .value
        guard let exercise = inserted.first else {
            throw RepositoryError.insertFailed
        }
        return exercise
    }
}
