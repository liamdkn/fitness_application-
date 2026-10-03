import Foundation
import Supabase

/// One ingredient line of a prep being built: a food plus its servings
/// multiplier (the same unit `FoodPickerView` hands back, so a weight
/// entered in grams arrives here already divided by the food's serving
/// size). `amount` converts back to the food's own unit for display.
struct PrepIngredient: Identifiable, Hashable {
    let id = UUID()
    var food: Food
    var quantity: Double

    var amount: Double { quantity * food.servingSize }
}

struct MealPrepRepository {
    let client = SupabaseService.shared.client
    private let recipeRepository = RecipeRepository()

    private struct NewPrepRecipe: Encodable {
        let user_id: UUID
        let name: String
        let serving_size: Double
        let serving_unit: String
        let calories: Double
        let protein_g: Double
        let carbs_g: Double
        let fat_g: Double
        let fiber_g: Double
        let is_meal_prep: Bool
    }

    private struct NewPrepIngredient: Encodable {
        let recipe_id: UUID
        let food_id: UUID
        let quantity: Double
    }

    private struct NewMealPrep: Encodable {
        let user_id: UUID
        let name: String
        let recipe_id: UUID
        let prepped_on: String
        let portions: Double
        let eat_within_days: Int
        let total_weight_g: Double?
    }

    private struct FinishedUpdate: Encodable {
        let finished_at: Date
    }

    func fetchAll() async throws -> [MealPrep] {
        try await client
            .from("meal_preps")
            .select()
            .order("prepped_on", ascending: false)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    /// Joins each prep with its per-portion recipe and how much of it has
    /// been logged so far, newest prep first.
    @MainActor
    func fetchSummaries() async throws -> [MealPrepSummary] {
        let preps = try await fetchAll()
        guard !preps.isEmpty else { return [] }
        let recipeIds = preps.map(\.recipeId)
        let recipes = try await recipeRepository.fetchByIds(recipeIds)
        let recipesById = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
        let eaten = await OfflineMealQueue.shared.eatenQuantities(recipeIds: recipeIds)
        return preps.compactMap { prep in
            guard let recipe = recipesById[prep.recipeId] else { return nil }
            return MealPrepSummary(prep: prep, recipe: recipe, eatenPortions: eaten[prep.recipeId] ?? 0)
        }
    }

    /// Ingredients of an existing prep with their foods resolved - the
    /// detail screen's list, and the starting point for "Prep again".
    func fetchIngredients(of prep: MealPrep) async throws -> [PrepIngredient] {
        let rows = try await recipeRepository.fetchIngredients(recipeId: prep.recipeId)
        let foods = try await FoodRepository().fetchByIds(Array(Set(rows.map(\.foodId))))
        let foodsById = Dictionary(uniqueKeysWithValues: foods.map { ($0.id, $0) })
        return rows.compactMap { row in
            foodsById[row.foodId].map { PrepIngredient(food: $0, quantity: row.quantity) }
        }
    }

    /// Creates the prep's own recipe (macros already divided down to one
    /// portion), its ingredients, then the prep row itself. If anything
    /// after the recipe insert fails the recipe is deleted again (which
    /// cascades to its ingredients) so a half-saved batch can't linger.
    @discardableResult
    func create(
        name: String,
        preppedOn: Date,
        portions: Double,
        eatWithinDays: Int,
        totalWeightG: Double?,
        ingredients: [PrepIngredient]
    ) async throws -> MealPrep {
        let userId = try await client.auth.session.user.id
        let batch = RecipeRepository.totals(for: ingredients.map { ($0.food, $0.quantity) })
        let perPortion = MealPrepCalculator.perPortion(batch, portions: portions)

        let recipes: [Recipe] = try await client
            .from("recipes")
            .insert(NewPrepRecipe(
                user_id: userId,
                name: name,
                serving_size: totalWeightG.map { $0 / portions } ?? 1,
                serving_unit: totalWeightG == nil ? "portion" : "g",
                calories: perPortion.calories,
                protein_g: perPortion.proteinG,
                carbs_g: perPortion.carbsG,
                fat_g: perPortion.fatG,
                fiber_g: perPortion.fiberG,
                is_meal_prep: true
            ))
            .select()
            .execute()
            .value
        guard let recipe = recipes.first else { throw RepositoryError.insertFailed }

        do {
            try await client
                .from("recipe_ingredients")
                .insert(ingredients.map { NewPrepIngredient(recipe_id: recipe.id, food_id: $0.food.id, quantity: $0.quantity) })
                .execute()
            let preps: [MealPrep] = try await client
                .from("meal_preps")
                .insert(NewMealPrep(
                    user_id: userId,
                    name: name,
                    recipe_id: recipe.id,
                    prepped_on: DateFormatting.isoDate(preppedOn),
                    portions: portions,
                    eat_within_days: eatWithinDays,
                    total_weight_g: totalWeightG
                ))
                .select()
                .execute()
                .value
            guard let prep = preps.first else { throw RepositoryError.insertFailed }
            return prep
        } catch {
            try? await recipeRepository.delete(id: recipe.id)
            throw error
        }
    }

    private struct FreezeUpdate: Encodable {
        let location = "freezer"
        let frozen_on: String
    }

    private struct ThawUpdate: Encodable {
        let location = "fridge"
        let thawed_on: String
    }

    /// Frozen batches stop counting down to their eat-by date.
    func freeze(id: UUID) async throws {
        try await client
            .from("meal_preps")
            .update(FreezeUpdate(frozen_on: DateFormatting.isoDate(Date())))
            .eq("id", value: id)
            .execute()
    }

    /// Back to the fridge - restarts the eat-by clock from today (see
    /// `MealPrep.eatBy`).
    func thaw(id: UUID) async throws {
        try await client
            .from("meal_preps")
            .update(ThawUpdate(thawed_on: DateFormatting.isoDate(Date())))
            .eq("id", value: id)
            .execute()
    }

    func markFinished(id: UUID) async throws {
        try await client
            .from("meal_preps")
            .update(FinishedUpdate(finished_at: Date()))
            .eq("id", value: id)
            .execute()
    }

    /// Only for a prep nothing has been logged against - `meal_entries`
    /// references the recipe, so a prep that's been eaten from is
    /// finished/archived instead.
    func delete(_ prep: MealPrep) async throws {
        try await recipeRepository.delete(id: prep.recipeId)
    }
}
