import Foundation
import Supabase

struct GymRepository {
    let client = SupabaseService.shared.client

    private struct NewGym: Encodable {
        let user_id: UUID
        let name: String
    }

    private struct RenameGym: Encodable {
        let name: String
    }

    func fetchAll() async throws -> [Gym] {
        try await client
            .from("gyms")
            .select()
            .order("name")
            .execute()
            .value
    }

    @discardableResult
    func create(name: String) async throws -> Gym {
        let userId = try await client.auth.session.user.id
        let inserted: [Gym] = try await client
            .from("gyms")
            .insert(NewGym(user_id: userId, name: name))
            .select()
            .execute()
            .value
        guard let gym = inserted.first else {
            throw RepositoryError.insertFailed
        }
        return gym
    }

    @discardableResult
    func rename(id: UUID, name: String) async throws -> Gym {
        let updated: [Gym] = try await client
            .from("gyms")
            .update(RenameGym(name: name))
            .eq("id", value: id)
            .select()
            .execute()
            .value
        guard let gym = updated.first else {
            throw RepositoryError.insertFailed
        }
        return gym
    }

    /// A gym referenced by a past workout isn't hard-deleted along with it -
    /// the workout's `gym_id` just goes null (`on delete set null`), so
    /// removing a gym never silently deletes training history.
    func delete(id: UUID) async throws {
        try await client
            .from("gyms")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}
