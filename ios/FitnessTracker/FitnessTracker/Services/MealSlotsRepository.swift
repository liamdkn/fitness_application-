import Foundation
import Supabase

struct MealSlotsRepository {
    let client = SupabaseService.shared.client

    /// Shipped default set on first use - still just ordinary rows the
    /// user can rename/reorder/delete/add to afterward, not a hardcoded
    /// enum anywhere else in the app.
    private static let defaultNames = ["Preworkout", "Breakfast", "Lunch", "Dinner", "Snacks"]

    private struct NewMealSlot: Encodable {
        let user_id: UUID
        let name: String
        let sort_order: Int
    }

    private struct RenameUpdate: Encodable {
        let name: String
    }

    private struct ReorderParams: Encodable {
        let p_ordered_ids: [UUID]
    }

    /// Provisions the default slots on first call for a user with none yet
    /// - matches how other per-user settings (e.g. `UserPreferences`) fall
    /// back to a default rather than requiring a signup-time DB trigger,
    /// adapted here for a table of rows instead of a single settings row.
    func fetchAll() async throws -> [MealSlot] {
        let existing: [MealSlot] = try await client
            .from("meal_slots")
            .select()
            .order("sort_order")
            .execute()
            .value
        guard existing.isEmpty else { return existing }

        let userId = try await client.auth.session.user.id
        let seeded = Self.defaultNames.enumerated().map { index, name in
            NewMealSlot(user_id: userId, name: name, sort_order: index)
        }
        return try await client
            .from("meal_slots")
            .insert(seeded)
            .select()
            .order("sort_order")
            .execute()
            .value
    }

    @discardableResult
    func add(name: String) async throws -> MealSlot {
        let userId = try await client.auth.session.user.id
        let existing: [MealSlot] = try await client
            .from("meal_slots")
            .select()
            .order("sort_order", ascending: false)
            .limit(1)
            .execute()
            .value
        let nextOrder = (existing.first?.sortOrder ?? -1) + 1
        let inserted: [MealSlot] = try await client
            .from("meal_slots")
            .insert(NewMealSlot(user_id: userId, name: name, sort_order: nextOrder))
            .select()
            .execute()
            .value
        guard let slot = inserted.first else {
            throw RepositoryError.insertFailed
        }
        return slot
    }

    @discardableResult
    func rename(id: UUID, name: String) async throws -> MealSlot {
        let updated: [MealSlot] = try await client
            .from("meal_slots")
            .update(RenameUpdate(name: name))
            .eq("id", value: id)
            .select()
            .execute()
            .value
        guard let slot = updated.first else {
            throw RepositoryError.insertFailed
        }
        return slot
    }

    /// `orderedIds` is every slot the user has, in its new display order -
    /// a single RPC call rather than N separate position updates, for the
    /// same reason `RoutineRepository.reorderExercises` is one call: a
    /// naive per-row update sequence can collide with (user_id, sort_order)
    /// mid-reshuffle.
    func reorder(orderedIds: [UUID]) async throws {
        try await client
            .rpc("reorder_meal_slots", params: ReorderParams(p_ordered_ids: orderedIds))
            .execute()
    }

    func delete(id: UUID) async throws {
        try await client
            .from("meal_slots")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}
