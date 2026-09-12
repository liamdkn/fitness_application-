import SwiftUI

/// Per-meal-slot log content, dropped directly into `NutritionEntryView`'s
/// Form - one Section per configured meal slot, each showing its logged
/// foods/recipes and a menu of ways to add more (a single food, a saved
/// recipe, or a whole saved meal in one action) plus "Save This Meal" once
/// there's something in the slot worth keeping.
struct MealLogSection: View {
    @ObservedObject var viewModel: MealLogViewModel
    let date: Date

    @State private var addingFoodToSlot: MealSlot?
    @State private var addingRecipeToSlot: MealSlot?
    @State private var addingSavedMealToSlot: MealSlot?
    @State private var savingSlot: MealSlot?

    var body: some View {
        ForEach(viewModel.slotGroups) { group in
            Section {
                ForEach(group.entries) { slotEntry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(slotEntry.name)
                            Text("\(quantityLabel(slotEntry.entry.quantity)) \u{00d7} \(slotEntry.servingLabel)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(slotEntry.calories)) kcal")
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in
                    let toDelete = offsets.map { group.entries[$0].entry }
                    Task {
                        for entry in toDelete {
                            await viewModel.deleteEntry(entry)
                        }
                    }
                }

                Menu {
                    Button {
                        addingFoodToSlot = group.slot
                    } label: {
                        Label("Add Food", systemImage: "plus")
                    }
                    Button {
                        addingRecipeToSlot = group.slot
                    } label: {
                        Label("Log Recipe", systemImage: "book")
                    }
                    Button {
                        addingSavedMealToSlot = group.slot
                    } label: {
                        Label("Log Saved Meal", systemImage: "list.bullet.rectangle")
                    }
                    if !group.entries.isEmpty {
                        Button {
                            savingSlot = group.slot
                        } label: {
                            Label("Save This Meal", systemImage: "bookmark")
                        }
                    }
                } label: {
                    Label("Add to \(group.slot.name)", systemImage: "plus")
                }
            } header: {
                HStack {
                    Text(group.slot.name)
                    Spacer()
                    if group.totalCalories > 0 {
                        Text("\(Int(group.totalCalories)) kcal")
                    }
                }
            }
        }
        .sheet(item: $addingFoodToSlot) { slot in
            FoodPickerView(mealSlotName: slot.name) { food, quantity in
                Task { await viewModel.logFood(food, quantity: quantity, mealSlotId: slot.id, date: date) }
            }
        }
        .sheet(item: $addingRecipeToSlot) { slot in
            RecipePickerView(mealSlotName: slot.name) { recipe, quantity in
                Task { await viewModel.logRecipe(recipe, quantity: quantity, mealSlotId: slot.id, date: date) }
            }
        }
        .sheet(item: $addingSavedMealToSlot) { slot in
            SavedMealPickerView(mealSlotName: slot.name) { items in
                Task { await viewModel.applySavedMeal(items, mealSlotId: slot.id, date: date) }
            }
        }
        .sheet(item: $savingSlot) { slot in
            SaveMealSheet(entries: viewModel.entries(forSlot: slot.id)) {}
        }
    }

    private func quantityLabel(_ quantity: Double) -> String {
        quantity == quantity.rounded() ? "\(Int(quantity))" : String(format: "%.1f", quantity)
    }
}
