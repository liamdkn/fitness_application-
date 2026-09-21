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
    var servingLabel: String { food?.servingLabel ?? recipe?.servingUnit ?? "" }
    var calories: Double { food?.calories(at: entry.quantity) ?? recipe?.calories(at: entry.quantity) ?? 0 }
    var proteinG: Double { food?.proteinG(at: entry.quantity) ?? recipe?.proteinG(at: entry.quantity) ?? 0 }
    var carbsG: Double { food?.carbsG(at: entry.quantity) ?? recipe?.carbsG(at: entry.quantity) ?? 0 }
    var fatG: Double { food?.fatG(at: entry.quantity) ?? recipe?.fatG(at: entry.quantity) ?? 0 }
    var fiberG: Double { food?.fiberG(at: entry.quantity) ?? recipe?.fiberG(at: entry.quantity) ?? 0 }
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
}

struct DayMacroTotals {
    var calories: Double = 0
    var proteinG: Double = 0
    var carbsG: Double = 0
    var fatG: Double = 0
    var fiberG: Double = 0
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

    func logFood(_ food: Food, quantity: Double, mealSlotId: UUID, date: Date) async {
        do {
            let entry = try offlineQueue.addFoodEntry(date: date, mealSlotId: mealSlotId, foodId: food.id, quantity: quantity)
            foodsById[food.id] = food
            entries.append(entry)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logRecipe(_ recipe: Recipe, quantity: Double, mealSlotId: UUID, date: Date) async {
        do {
            let entry = try offlineQueue.addRecipeEntry(date: date, mealSlotId: mealSlotId, recipeId: recipe.id, quantity: quantity)
            recipesById[recipe.id] = recipe
            entries.append(entry)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteEntry(_ entry: MealEntry) async {
        do {
            try await offlineQueue.deleteEntry(id: entry.id)
            entries.removeAll { $0.id == entry.id }
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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func repeatDay(from sourceDate: Date, to targetDate: Date) async {
        do {
            let copied = try await mealEntryRepository.copyEntries(from: sourceDate, to: targetDate)
            entries.append(contentsOf: copied)
            await fetchMissingReferences(for: copied)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applySavedMeal(_ items: [SavedMealItem], mealSlotId: UUID, date: Date) async {
        do {
            let applied = try await mealEntryRepository.applySavedMealItems(items, date: date, mealSlotId: mealSlotId)
            entries.append(contentsOf: applied)
            await fetchMissingReferences(for: applied)
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
            let applied = try await mealEntryRepository.applySavedDayItems(items, date: date)
            entries.append(contentsOf: applied)
            await fetchMissingReferences(for: applied)
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
