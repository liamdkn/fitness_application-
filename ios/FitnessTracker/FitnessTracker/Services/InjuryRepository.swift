import Foundation
import Supabase

struct InjuryRepository {
    let client = SupabaseService.shared.client

    private struct NewInjury: Encodable {
        let user_id: UUID
        let muscle_group: String
        let notes: String?
        let started_at: String
    }

    private struct ResolveUpdate: Encodable {
        let resolved_at: String
    }

    func fetchAll() async throws -> [Injury] {
        try await client
            .from("injuries")
            .select()
            .order("started_at", ascending: false)
            .execute()
            .value
    }

    /// Just the muscle groups with an unresolved injury - all the active
    /// workout screen needs to decide whether to show a warning, without
    /// pulling notes/dates it doesn't use.
    func fetchActiveMuscleGroups() async throws -> Set<String> {
        let injuries: [Injury] = try await client
            .from("injuries")
            .select("id, muscle_group, notes, started_at, resolved_at")
            .is("resolved_at", value: nil)
            .execute()
            .value
        return Set(injuries.map(\.muscleGroup))
    }

    func addInjury(muscleGroup: String, notes: String?, startedAt: Date) async throws -> Injury {
        let userId = try await client.auth.session.user.id
        let inserted: [Injury] = try await client
            .from("injuries")
            .insert(NewInjury(
                user_id: userId,
                muscle_group: muscleGroup,
                notes: notes?.isEmpty == true ? nil : notes,
                started_at: DateFormatting.isoDate(startedAt)
            ))
            .select()
            .execute()
            .value
        guard let injury = inserted.first else {
            throw RepositoryError.insertFailed
        }
        return injury
    }

    func resolveInjury(id: UUID) async throws -> Injury {
        let updated: [Injury] = try await client
            .from("injuries")
            .update(ResolveUpdate(resolved_at: DateFormatting.isoDate(Date())))
            .eq("id", value: id)
            .select()
            .execute()
            .value
        guard let injury = updated.first else {
            throw RepositoryError.insertFailed
        }
        return injury
    }

    func deleteInjury(id: UUID) async throws {
        try await client
            .from("injuries")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}
