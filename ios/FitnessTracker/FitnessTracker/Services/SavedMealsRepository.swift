import Foundation
import Supabase

struct SavedMealsRepository {
    let client = SupabaseService.shared.client

    private struct NewSavedMeal: Encodable {
        let user_id: UUID
        let name: String
    }

    private struct NewSavedMealItem: Encodable {
        let saved_meal_id: UUID
        let food_id: UUID?
        let recipe_id: UUID?
        let quantity: Double
    }

    func fetchAll() async throws -> [SavedMeal] {
        try await client
            .from("saved_meals")
            .select()
            .order("name")
            .execute()
            .value
    }

    func fetchItems(savedMealId: UUID) async throws -> [SavedMealItem] {
        try await client
            .from("saved_meal_items")
            .select()
            .eq("saved_meal_id", value: savedMealId)
            .execute()
            .value
    }

    /// Snapshots `entries` (a meal slot's already-logged entries for some
    /// day) into a new named saved meal - a copy, not a live reference, so
    /// a later edit to the source day (or to a food/recipe it used) never
    /// changes what this saved meal applies.
    @discardableResult
    func save(name: String, entries: [MealEntry]) async throws -> SavedMeal {
        let userId = try await client.auth.session.user.id
        let inserted: [SavedMeal] = try await client
            .from("saved_meals")
            .insert(NewSavedMeal(user_id: userId, name: name))
            .select()
            .execute()
            .value
        guard let savedMeal = inserted.first else {
            throw RepositoryError.insertFailed
        }
        guard !entries.isEmpty else { return savedMeal }
        let rows = entries.map { entry in
            NewSavedMealItem(saved_meal_id: savedMeal.id, food_id: entry.foodId, recipe_id: entry.recipeId, quantity: entry.quantity)
        }
        try await client.from("saved_meal_items").insert(rows).execute()
        return savedMeal
    }

    func delete(id: UUID) async throws {
        try await client
            .from("saved_meals")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}
