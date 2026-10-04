import Foundation
import Supabase

struct SavedDaysRepository {
    let client = SupabaseService.shared.client

    private struct NewSavedDay: Encodable {
        let user_id: UUID
        let name: String
        let calories: Double
        let protein_g: Double
        let carbs_g: Double
        let fat_g: Double
        let fiber_g: Double
    }

    private struct NewSavedDayItem: Encodable {
        let saved_day_id: UUID
        let meal_slot_id: UUID
        let food_id: UUID?
        let recipe_id: UUID?
        let quantity: Double
    }

    func fetchAll() async throws -> [SavedDay] {
        try await cachedRead(key: "saved-days") {
            try await client
                .from("saved_days")
                .select()
                .order("name")
                .execute()
                .value
        }
    }

    /// Also pulls in the items' foods and recipes, so a saved day can be
    /// applied later with no connection.
    func fetchItems(savedDayId: UUID) async throws -> [SavedDayItem] {
        let items: [SavedDayItem] = try await cachedRead(key: "saved-day-items-\(savedDayId)") {
            try await client
                .from("saved_day_items")
                .select()
                .eq("saved_day_id", value: savedDayId)
                .execute()
                .value
        }
        _ = try? await FoodRepository().fetchByIds(items.compactMap(\.foodId))
        _ = try? await RecipeRepository().fetchByIds(items.compactMap(\.recipeId))
        return items
    }

    /// Snapshots every meal slot's current entries (`entries`, across the
    /// whole day) into a new named saved day, with `totals` (the day's
    /// already-computed macro sum) cached on the row - a copy, not a live
    /// reference, so later edits to the source day or its foods/recipes
    /// never change it.
    @discardableResult
    func save(name: String, totals: DayMacroTotals, entries: [MealEntry]) async throws -> SavedDay {
        let userId = try await client.auth.session.user.id
        let inserted: [SavedDay] = try await client
            .from("saved_days")
            .insert(NewSavedDay(
                user_id: userId,
                name: name,
                calories: totals.calories,
                protein_g: totals.proteinG,
                carbs_g: totals.carbsG,
                fat_g: totals.fatG,
                fiber_g: totals.fiberG
            ))
            .select()
            .execute()
            .value
        guard let savedDay = inserted.first else {
            throw RepositoryError.insertFailed
        }
        guard !entries.isEmpty else { return savedDay }
        let rows = entries.map { entry in
            NewSavedDayItem(
                saved_day_id: savedDay.id,
                meal_slot_id: entry.mealSlotId,
                food_id: entry.foodId,
                recipe_id: entry.recipeId,
                quantity: entry.quantity
            )
        }
        try await client.from("saved_day_items").insert(rows).execute()
        return savedDay
    }

    func delete(id: UUID) async throws {
        try await client
            .from("saved_days")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}
