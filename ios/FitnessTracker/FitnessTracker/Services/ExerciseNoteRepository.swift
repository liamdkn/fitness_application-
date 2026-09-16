import Foundation
import Supabase

struct ExerciseNoteRepository {
    let client = SupabaseService.shared.client

    private struct UpsertExerciseNote: Encodable {
        let user_id: UUID
        let workout_id: UUID
        let exercise_id: UUID
        let note: String
    }

    func fetchNote(workoutId: UUID, exerciseId: UUID) async throws -> ExerciseNote? {
        let notes: [ExerciseNote] = try await client
            .from("exercise_notes")
            .select()
            .eq("workout_id", value: workoutId)
            .eq("exercise_id", value: exerciseId)
            .limit(1)
            .execute()
            .value
        return notes.first
    }

    /// Every note logged for this exercise across every past workout, most
    /// recent first - powers `ExerciseHistoryView`.
    func fetchNotes(exerciseId: UUID) async throws -> [ExerciseNote] {
        try await client
            .from("exercise_notes")
            .select()
            .eq("exercise_id", value: exerciseId)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    @discardableResult
    func upsertNote(workoutId: UUID, exerciseId: UUID, note: String) async throws -> ExerciseNote {
        let userId = try await client.auth.session.user.id
        let rows: [ExerciseNote] = try await client
            .from("exercise_notes")
            .upsert(
                UpsertExerciseNote(user_id: userId, workout_id: workoutId, exercise_id: exerciseId, note: note),
                onConflict: "workout_id,exercise_id"
            )
            .select()
            .execute()
            .value
        guard let row = rows.first else {
            throw RepositoryError.insertFailed
        }
        return row
    }
}
