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
