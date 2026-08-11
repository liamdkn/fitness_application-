import Foundation
import Supabase

struct ProgressionRepository {
    let client = SupabaseService.shared.client

    func fetchProgression(exerciseId: UUID) async throws -> [ExerciseProgressionPoint] {
        try await client
            .from("v_exercise_progression")
            .select()
            .eq("exercise_id", value: exerciseId)
            .order("performed_at")
            .execute()
            .value
    }
}
