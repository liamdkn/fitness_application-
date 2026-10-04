import Foundation
import Supabase

struct RecipeRepository {
    let client = SupabaseService.shared.client

    func fetchByIds(_ ids: [UUID]) async throws -> [Recipe] {
        guard !ids.isEmpty else { return [] }
        do {
            let recipes: [Recipe] = try await client
                .from("recipes")
                .select()
                .in("id", values: ids)
                .execute()
                .value
            Caches.recipes.store(recipes)
            return recipes
        } catch {
            guard OfflineError.isConnectivity(error) else { throw error }
            return Caches.recipes.items(ids: ids)
        }
    }

    func fetchIngredients(recipeId: UUID) async throws -> [RecipeIngredient] {
        try await client
            .from("recipe_ingredients")
            .select()
            .eq("recipe_id", value: recipeId)
            .execute()
            .value
    }

    func delete(id: UUID) async throws {
        try await client
            .from("recipes")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    static func totals(for ingredients: [(food: Food, quantity: Double)]) -> DayMacroTotals {
        var totals = DayMacroTotals()
        for (food, quantity) in ingredients {
            totals.calories += food.calories(at: quantity)
            totals.proteinG += food.proteinG(at: quantity)
            totals.carbsG += food.carbsG(at: quantity)
            totals.fatG += food.fatG(at: quantity)
            totals.fiberG += food.fiberG(at: quantity) ?? 0
        }
        return totals
    }
}
