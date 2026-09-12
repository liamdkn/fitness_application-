import Foundation
import Supabase

struct RecipeRepository {
    let client = SupabaseService.shared.client

    private struct NewRecipe: Encodable {
        let user_id: UUID
        let name: String
        let serving_size: Double
        let serving_unit: String
        let calories: Double
        let protein_g: Double
        let carbs_g: Double
        let fat_g: Double
        let fiber_g: Double
    }

    private struct NewRecipeIngredient: Encodable {
        let recipe_id: UUID
        let food_id: UUID
        let quantity: Double
    }

    func fetchAll() async throws -> [Recipe] {
        try await client
            .from("recipes")
            .select()
            .order("name")
            .execute()
            .value
    }

    func fetchByIds(_ ids: [UUID]) async throws -> [Recipe] {
        guard !ids.isEmpty else { return [] }
        return try await client
            .from("recipes")
            .select()
            .in("id", values: ids)
            .execute()
            .value
    }

    func fetchIngredients(recipeId: UUID) async throws -> [RecipeIngredient] {
        try await client
            .from("recipe_ingredients")
            .select()
            .eq("recipe_id", value: recipeId)
            .execute()
            .value
    }

    /// Totals are computed here, client-side, from each ingredient food's
    /// own per-serving macros times its quantity, and cached on the new
    /// recipe row rather than derived live on every future read - see
    /// `Recipe`'s doc comment.
    @discardableResult
    func create(name: String, ingredients: [(food: Food, quantity: Double)]) async throws -> Recipe {
        let userId = try await client.auth.session.user.id
        let totals = Self.totals(for: ingredients)
        let inserted: [Recipe] = try await client
            .from("recipes")
            .insert(NewRecipe(
                user_id: userId,
                name: name,
                serving_size: 1,
                serving_unit: "serving",
                calories: totals.calories,
                protein_g: totals.proteinG,
                carbs_g: totals.carbsG,
                fat_g: totals.fatG,
                fiber_g: totals.fiberG
            ))
            .select()
            .execute()
            .value
        guard let recipe = inserted.first else {
            throw RepositoryError.insertFailed
        }
        guard !ingredients.isEmpty else { return recipe }
        let rows = ingredients.map { NewRecipeIngredient(recipe_id: recipe.id, food_id: $0.food.id, quantity: $0.quantity) }
        try await client.from("recipe_ingredients").insert(rows).execute()
        return recipe
    }

    func delete(id: UUID) async throws {
        try await client
            .from("recipes")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    private static func totals(for ingredients: [(food: Food, quantity: Double)]) -> DayMacroTotals {
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
