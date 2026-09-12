import Foundation
import Supabase

struct MealEntryRepository {
    let client = SupabaseService.shared.client

    /// Exactly one of `food_id`/`recipe_id` is non-nil - matches the
    /// `meal_entries` check constraint. A recipe logs into a meal slot the
    /// same way a plain food does.
    private struct NewMealEntry: Encodable {
        let user_id: UUID
        let date: String
        let meal_slot_id: UUID
        let food_id: UUID?
        let recipe_id: UUID?
        let quantity: Double
    }

    /// Explicit-id variant of `NewMealEntry`, for `upsertEntry` -
    /// `OfflineMealQueue` generates the id client-side up front, before the
    /// row exists on the server at all, so replaying this after a partial
    /// flush failure just re-applies the same row rather than erroring on
    /// a duplicate id or creating a second one.
    private struct UpsertMealEntry: Encodable {
        let id: UUID
        let user_id: UUID
        let date: String
        let meal_slot_id: UUID
        let food_id: UUID?
        let recipe_id: UUID?
        let quantity: Double
        let logged_at: Date
    }

    private struct QuantityUpdate: Encodable {
        let quantity: Double
    }

    func fetchEntries(date: Date) async throws -> [MealEntry] {
        try await client
            .from("meal_entries")
            .select()
            .eq("date", value: DateFormatting.isoDate(date))
            .order("logged_at")
            .execute()
            .value
    }

    /// Every entry within an inclusive calendar range - used for the
    /// day-to-day trend/history reads once those become cutover-aware
    /// (Section 4 of the nutrition rebuild plan), same shape as
    /// `NutritionRepository.fetchRange`.
    func fetchEntries(from: Date, to: Date) async throws -> [MealEntry] {
        try await client
            .from("meal_entries")
            .select()
            .gte("date", value: DateFormatting.isoDate(from))
            .lte("date", value: DateFormatting.isoDate(to))
            .order("date")
            .execute()
            .value
    }

    @discardableResult
    func addFoodEntry(date: Date, mealSlotId: UUID, foodId: UUID, quantity: Double) async throws -> MealEntry {
        try await insert(NewMealEntry(
            user_id: try await client.auth.session.user.id,
            date: DateFormatting.isoDate(date),
            meal_slot_id: mealSlotId,
            food_id: foodId,
            recipe_id: nil,
            quantity: quantity
        ))
    }

    @discardableResult
    func addRecipeEntry(date: Date, mealSlotId: UUID, recipeId: UUID, quantity: Double) async throws -> MealEntry {
        try await insert(NewMealEntry(
            user_id: try await client.auth.session.user.id,
            date: DateFormatting.isoDate(date),
            meal_slot_id: mealSlotId,
            food_id: nil,
            recipe_id: recipeId,
            quantity: quantity
        ))
    }

    @discardableResult
    func updateQuantity(id: UUID, quantity: Double) async throws -> MealEntry {
        let updated: [MealEntry] = try await client
            .from("meal_entries")
            .update(QuantityUpdate(quantity: quantity))
            .eq("id", value: id)
            .select()
            .execute()
            .value
        guard let entry = updated.first else {
            throw RepositoryError.insertFailed
        }
        return entry
    }

    func deleteEntry(id: UUID) async throws {
        try await client
            .from("meal_entries")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    /// Copies every entry from `sourceDate` onto `targetDate` - the "repeat
    /// yesterday"/"repeat [date]" action. A plain bulk insert of new rows,
    /// not a reference to the source day, so editing the copy never
    /// touches the original.
    @discardableResult
    func copyEntries(from sourceDate: Date, to targetDate: Date) async throws -> [MealEntry] {
        let sourceEntries = try await fetchEntries(date: sourceDate)
        guard !sourceEntries.isEmpty else { return [] }
        let userId = try await client.auth.session.user.id
        let targetDateString = DateFormatting.isoDate(targetDate)
        let copies = sourceEntries.map { entry in
            NewMealEntry(
                user_id: userId,
                date: targetDateString,
                meal_slot_id: entry.mealSlotId,
                food_id: entry.foodId,
                recipe_id: entry.recipeId,
                quantity: entry.quantity
            )
        }
        return try await insertAll(copies)
    }

    /// Applies a saved meal's items to any target date/slot in one action -
    /// the same underlying mechanism as `copyEntries`, just sourced from
    /// `saved_meal_items` instead of another day's `meal_entries`.
    @discardableResult
    func applySavedMealItems(_ items: [SavedMealItem], date: Date, mealSlotId: UUID) async throws -> [MealEntry] {
        guard !items.isEmpty else { return [] }
        let userId = try await client.auth.session.user.id
        let dateString = DateFormatting.isoDate(date)
        let rows = items.map { item in
            NewMealEntry(
                user_id: userId,
                date: dateString,
                meal_slot_id: mealSlotId,
                food_id: item.foodId,
                recipe_id: item.recipeId,
                quantity: item.quantity
            )
        }
        return try await insertAll(rows)
    }

    /// Applies a saved day's items (across every slot it covers) to any
    /// target date in one action - the "repeat a saved day" counterpart to
    /// `applySavedMealItems`, just sourced from `saved_day_items` and using
    /// each item's own `mealSlotId` rather than one caller-specified slot.
    @discardableResult
    func applySavedDayItems(_ items: [SavedDayItem], date: Date) async throws -> [MealEntry] {
        guard !items.isEmpty else { return [] }
        let userId = try await client.auth.session.user.id
        let dateString = DateFormatting.isoDate(date)
        let rows = items.map { item in
            NewMealEntry(
                user_id: userId,
                date: dateString,
                meal_slot_id: item.mealSlotId,
                food_id: item.foodId,
                recipe_id: item.recipeId,
                quantity: item.quantity
            )
        }
        return try await insertAll(rows)
    }

    /// Used only by `OfflineMealQueue` to push a locally-queued entry (or
    /// its later edits) to Supabase - see `UpsertMealEntry`.
    func upsertEntry(
        id: UUID,
        date: String,
        mealSlotId: UUID,
        foodId: UUID?,
        recipeId: UUID?,
        quantity: Double,
        loggedAt: Date
    ) async throws {
        let userId = try await client.auth.session.user.id
        try await client
            .from("meal_entries")
            .upsert(
                UpsertMealEntry(
                    id: id,
                    user_id: userId,
                    date: date,
                    meal_slot_id: mealSlotId,
                    food_id: foodId,
                    recipe_id: recipeId,
                    quantity: quantity,
                    logged_at: loggedAt
                ),
                onConflict: "id"
            )
            .execute()
    }

    private func insert(_ row: NewMealEntry) async throws -> MealEntry {
        let inserted: [MealEntry] = try await client
            .from("meal_entries")
            .insert(row)
            .select()
            .execute()
            .value
        guard let entry = inserted.first else {
            throw RepositoryError.insertFailed
        }
        return entry
    }

    private func insertAll(_ rows: [NewMealEntry]) async throws -> [MealEntry] {
        guard !rows.isEmpty else { return [] }
        return try await client
            .from("meal_entries")
            .insert(rows)
            .select()
            .execute()
            .value
    }
}
