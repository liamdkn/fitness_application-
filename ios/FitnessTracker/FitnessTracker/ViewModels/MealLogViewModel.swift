import Combine
import Foundation

/// One meal slot's logged entries, each paired with whichever of
/// food/recipe it references (or both nil while still loading/missing) -
/// what `MealLogSection` actually renders per slot.
struct MealSlotEntry: Identifiable {
    let entry: MealEntry
    let food: Food?
    let recipe: Recipe?
    var id: UUID { entry.id }

    var name: String { food?.displayName ?? recipe?.name ?? "" }
    /// Name without the brand, for a card that shows the brand on its own line.
    var title: String { food?.name ?? recipe?.name ?? "" }
    var brand: String? { food?.brand.flatMap { $0.isEmpty ? nil : $0 } }
    var isVerified: Bool { food?.isVerified ?? false }
    var isMealPrep: Bool { recipe != nil }
    /// Which part of the meal this sits under: its food's main category;
    /// recipes and uncategorised foods fall under Other.
    var category: FoodCategory { food?.primaryCategory ?? .other }
    var servingLabel: String { food?.servingLabel ?? recipe?.servingUnit ?? "" }
    /// What was actually eaten ("80g", "250ml", "2 egg") rather than the raw
    /// servings multiplier ("0.8 x 100g") - see `AmountLabel`.
    var amountLabel: String {
        food?.amountLabel(at: entry.quantity) ?? recipe?.amountLabel(at: entry.quantity) ?? ""
    }
    var calories: Double { food?.calories(at: entry.quantity) ?? recipe?.calories(at: entry.quantity) ?? 0 }
    var proteinG: Double { food?.proteinG(at: entry.quantity) ?? recipe?.proteinG(at: entry.quantity) ?? 0 }
    var carbsG: Double { food?.carbsG(at: entry.quantity) ?? recipe?.carbsG(at: entry.quantity) ?? 0 }
    var fatG: Double { food?.fatG(at: entry.quantity) ?? recipe?.fatG(at: entry.quantity) ?? 0 }
    var fiberG: Double { food?.fiberG(at: entry.quantity) ?? recipe?.fiberG(at: entry.quantity) ?? 0 }
    /// Only foods carry sodium/caffeine (a recipe doesn't, yet) - 0 means
    /// "none recorded", which for sodium also covers foods nobody's entered it for.
    var sodiumMg: Double { food?.sodiumMg(at: entry.quantity) ?? 0 }
    var caffeineMg: Double { food?.caffeineMg(at: entry.quantity) ?? 0 }
    /// Millilitres, for drinks only.
    var volumeMl: Double { food?.volumeMl(at: entry.quantity) ?? 0 }
}

struct MealSlotGroup: Identifiable {
    let slot: MealSlot
    let entries: [MealSlotEntry]
    var id: UUID { slot.id }

    var totalCalories: Double { entries.reduce(0) { $0 + $1.calories } }
    var totalProteinG: Double { entries.reduce(0) { $0 + $1.proteinG } }
    var totalCarbsG: Double { entries.reduce(0) { $0 + $1.carbsG } }
    var totalFatG: Double { entries.reduce(0) { $0 + $1.fatG } }
    var totalFiberG: Double { entries.reduce(0) { $0 + $1.fiberG } }
    var totalSodiumMg: Double { entries.reduce(0) { $0 + $1.sodiumMg } }
    var totalCaffeineMg: Double { entries.reduce(0) { $0 + $1.caffeineMg } }
    var totalVolumeMl: Double { entries.reduce(0) { $0 + $1.volumeMl } }
}

struct DayMacroTotals {
    var calories: Double = 0
    var proteinG: Double = 0
    var carbsG: Double = 0
    var fatG: Double = 0
    var fiberG: Double = 0
    var sodiumMg: Double = 0
    var caffeineMg: Double = 0
}

@MainActor
final class MealLogViewModel: ObservableObject {
    @Published var mealSlots: [MealSlot] = []
    @Published var entries: [MealEntry] = []
    @Published var foodsById: [UUID: Food] = [:]
    @Published var recipesById: [UUID: Recipe] = [:]
    @Published var errorMessage: String?

    private let mealSlotsRepository = MealSlotsRepository()
    private let mealEntryRepository = MealEntryRepository()
    private let foodRepository = FoodRepository()
    private let recipeRepository = RecipeRepository()
    private let offlineQueue = OfflineMealQueue.shared

    var slotGroups: [MealSlotGroup] {
        mealSlots.map { slot in
            let slotEntries = entries
                .filter { $0.mealSlotId == slot.id }
                .map { entry in
                    MealSlotEntry(
                        entry: entry,
                        food: entry.foodId.flatMap { foodsById[$0] },
                        recipe: entry.recipeId.flatMap { recipesById[$0] }
                    )
                }
            return MealSlotGroup(slot: slot, entries: slotEntries)
        }
    }

    var dayTotals: DayMacroTotals {
        var totals = DayMacroTotals()
        for entry in entries {
            if let foodId = entry.foodId, let food = foodsById[foodId] {
                totals.calories += food.calories(at: entry.quantity)
                totals.proteinG += food.proteinG(at: entry.quantity)
                totals.carbsG += food.carbsG(at: entry.quantity)
                totals.fatG += food.fatG(at: entry.quantity)
                totals.fiberG += food.fiberG(at: entry.quantity) ?? 0
                totals.sodiumMg += food.sodiumMg(at: entry.quantity) ?? 0
                totals.caffeineMg += food.caffeineMg(at: entry.quantity) ?? 0
            } else if let recipeId = entry.recipeId, let recipe = recipesById[recipeId] {
                totals.calories += recipe.calories(at: entry.quantity)
                totals.proteinG += recipe.proteinG(at: entry.quantity)
                totals.carbsG += recipe.carbsG(at: entry.quantity)
                totals.fatG += recipe.fatG(at: entry.quantity)
                totals.fiberG += recipe.fiberG(at: entry.quantity)
            }
        }
        return totals
    }

    func loadMealSlots() async {
        do {
            mealSlots = try await mealSlotsRepository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Local-first via `OfflineMealQueue` - a day partly logged with no
    /// signal still shows everything the moment this reloads, connected
    /// or not.
    func loadEntries(date: Date) async {
        do {
            entries = try await offlineQueue.fetchEntries(date: date)
            await fetchMissingReferences(for: entries)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Today's widgets show meal totals, so they're refreshed after every
    /// change to the log (a no-op if nothing they show actually changed).
    private func refreshWidgets() {
        Task { await WidgetSnapshotService.shared.refresh(force: true) }
    }

    func logFood(_ food: Food, quantity: Double, mealSlotId: UUID, date: Date) async {
        do {
            let entry = try offlineQueue.addFoodEntry(date: date, mealSlotId: mealSlotId, foodId: food.id, quantity: quantity)
            foodsById[food.id] = food
            entries.append(entry)
            refreshWidgets()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logRecipe(_ recipe: Recipe, quantity: Double, mealSlotId: UUID, date: Date) async {
        do {
            let entry = try offlineQueue.addRecipeEntry(date: date, mealSlotId: mealSlotId, recipeId: recipe.id, quantity: quantity)
            recipesById[recipe.id] = recipe
            entries.append(entry)
            refreshWidgets()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteEntry(_ entry: MealEntry) async {
        do {
            try await offlineQueue.deleteEntry(id: entry.id)
            entries.removeAll { $0.id == entry.id }
            refreshWidgets()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateQuantity(_ entry: MealEntry, quantity: Double) async {
        do {
            let updated = try await offlineQueue.updateQuantity(id: entry.id, quantity: quantity)
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[index] = updated
            }
            refreshWidgets()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateEatenAt(_ entry: MealEntry, eatenAt: Date?) async {
        do {
            let updated = try await offlineQueue.updateEatenAt(id: entry.id, eatenAt: eatenAt)
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[index] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Copies a day's entries onto another day. Goes through the offline
    /// queue like any single log, so it works with no connection (the source
    /// day is read local-first too).
    func repeatDay(from sourceDate: Date, to targetDate: Date) async {
        do {
            let source = try await offlineQueue.fetchEntries(date: sourceDate)
            let copied = try source.map {
                try queueEntry(date: targetDate, mealSlotId: $0.mealSlotId, foodId: $0.foodId, recipeId: $0.recipeId, quantity: $0.quantity)
            }
            entries.append(contentsOf: copied)
            await fetchMissingReferences(for: copied)
            refreshWidgets()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applySavedMeal(_ items: [SavedMealItem], mealSlotId: UUID, date: Date) async {
        do {
            let applied = try items.map {
                try queueEntry(date: date, mealSlotId: mealSlotId, foodId: $0.foodId, recipeId: $0.recipeId, quantity: $0.quantity)
            }
            entries.append(contentsOf: applied)
            await fetchMissingReferences(for: applied)
            refreshWidgets()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// One food or recipe entry added through the offline queue.
    private func queueEntry(date: Date, mealSlotId: UUID, foodId: UUID?, recipeId: UUID?, quantity: Double) throws -> MealEntry {
        if let foodId {
            return try offlineQueue.addFoodEntry(date: date, mealSlotId: mealSlotId, foodId: foodId, quantity: quantity, stampEatenTime: false)
        }
        if let recipeId {
            return try offlineQueue.addRecipeEntry(date: date, mealSlotId: mealSlotId, recipeId: recipeId, quantity: quantity, stampEatenTime: false)
        }
        throw RepositoryError.insertFailed
    }

    /// Logs copies of entries from another day (see `CopyMealView`) into a
    /// slot on `date` - new rows through the offline queue, so it works with
    /// no connection and editing the copies leaves the originals alone.
    func copyEntries(_ source: [MealEntry], mealSlotId: UUID, date: Date) async {
        do {
            let copied = try source.map {
                try queueEntry(date: date, mealSlotId: mealSlotId, foodId: $0.foodId, recipeId: $0.recipeId, quantity: $0.quantity)
            }
            entries.append(contentsOf: copied)
            await fetchMissingReferences(for: copied)
            refreshWidgets()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Entries for one slot, as they stand right now - the source data for
    /// "Save This Meal".
    func entries(forSlot slotId: UUID) -> [MealEntry] {
        entries.filter { $0.mealSlotId == slotId }
    }

    func applySavedDay(_ items: [SavedDayItem], date: Date) async {
        do {
            let applied = try items.map {
                try queueEntry(date: date, mealSlotId: $0.mealSlotId, foodId: $0.foodId, recipeId: $0.recipeId, quantity: $0.quantity)
            }
            entries.append(contentsOf: applied)
            await fetchMissingReferences(for: applied)
            refreshWidgets()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func fetchMissingReferences(for newEntries: [MealEntry]) async {
        let missingFoodIds = Set(newEntries.compactMap(\.foodId)).subtracting(foodsById.keys)
        if !missingFoodIds.isEmpty, let fetched = try? await foodRepository.fetchByIds(Array(missingFoodIds)) {
            for food in fetched { foodsById[food.id] = food }
        }
        let missingRecipeIds = Set(newEntries.compactMap(\.recipeId)).subtracting(recipesById.keys)
        if !missingRecipeIds.isEmpty, let fetched = try? await recipeRepository.fetchByIds(Array(missingRecipeIds)) {
            for recipe in fetched { recipesById[recipe.id] = recipe }
        }
    }
}
