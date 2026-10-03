import Foundation
import Supabase

struct SavedMealsRepository {
    let client = SupabaseService.shared.client

    private struct NewSavedMeal: Encodable {
        let user_id: UUID
        let name: String
        let category: String?
    }

    /// `category` is encoded as an explicit null (not skipped) so clearing a
    /// meal's category actually clears it.
    private struct CategoryUpdate: Encodable {
        let category: String?

        enum CodingKeys: String, CodingKey { case category }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(category, forKey: .category)
        }
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
    func save(name: String, category: String? = nil, entries: [MealEntry]) async throws -> SavedMeal {
        let userId = try await client.auth.session.user.id
        let inserted: [SavedMeal] = try await client
            .from("saved_meals")
            .insert(NewSavedMeal(user_id: userId, name: name, category: Self.cleaned(category)))
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

    /// Every category currently in use, alphabetical - what the save sheet
    /// offers to file a new meal under.
    func fetchCategories() async throws -> [String] {
        let meals = try await fetchAll()
        return Array(Set(meals.compactMap { Self.cleaned($0.category) })).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func updateCategory(id: UUID, category: String?) async throws {
        try await client
            .from("saved_meals")
            .update(CategoryUpdate(category: Self.cleaned(category)))
            .eq("id", value: id)
            .execute()
    }

    /// Blank means uncategorised.
    private static func cleaned(_ category: String?) -> String? {
        let trimmed = category?.trimmingCharacters(in: .whitespaces) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func delete(id: UUID) async throws {
        try await client
            .from("saved_meals")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}
