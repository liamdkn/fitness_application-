import SwiftUI

/// One slot's entries and logging actions, pushed from `MealSlotListView`.
/// Reuses the exact same sheet flow the old `MealLogSection` offered inline
/// per-slot (Add Food / Log Recipe / Log Saved Meal / Save This Meal) -
/// just as its own screen instead of a Form section, since slots now show
/// as cards in a list rather than all stacked in one Form.
struct MealSlotDetailView: View {
    @ObservedObject var viewModel: MealLogViewModel
    let slot: MealSlot
    let date: Date

    @State private var addingFood = false
    @State private var addingRecipe = false
    @State private var addingSavedMeal = false
    @State private var isSavingMeal = false

    private var group: MealSlotGroup? {
        viewModel.slotGroups.first { $0.slot.id == slot.id }
    }

    private var entries: [MealSlotEntry] {
        group?.entries ?? []
    }

    var body: some View {
        List {
            if let group, !entries.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(Int(group.totalCalories)) cal")
                            .font(.title2.bold())
                        HStack(spacing: 16) {
                            macroText("C", group.totalCarbsG)
                            macroText("F", group.totalFatG)
                            macroText("P", group.totalProteinG)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                ForEach(entries) { slotEntry in
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
                    let toDelete = offsets.map { entries[$0].entry }
                    Task {
                        for entry in toDelete {
                            await viewModel.deleteEntry(entry)
                        }
                    }
                }
            } footer: {
                if entries.isEmpty {
                    Text("Nothing logged for \(slot.name) yet.")
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .navigationTitle(slot.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        addingFood = true
                    } label: {
                        Label("Add Food", systemImage: "plus")
                    }
                    Button {
                        addingRecipe = true
                    } label: {
                        Label("Log Recipe", systemImage: "book")
                    }
                    Button {
                        addingSavedMeal = true
                    } label: {
                        Label("Log Saved Meal", systemImage: "list.bullet.rectangle")
                    }
                    if !entries.isEmpty {
                        Button {
                            isSavingMeal = true
                        } label: {
                            Label("Save This Meal", systemImage: "bookmark")
                        }
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
        }
        .sheet(isPresented: $addingFood) {
            FoodPickerView(mealSlotName: slot.name) { food, quantity in
                Task { await viewModel.logFood(food, quantity: quantity, mealSlotId: slot.id, date: date) }
            }
        }
        .sheet(isPresented: $addingRecipe) {
            RecipePickerView(mealSlotName: slot.name) { recipe, quantity in
                Task { await viewModel.logRecipe(recipe, quantity: quantity, mealSlotId: slot.id, date: date) }
            }
        }
        .sheet(isPresented: $addingSavedMeal) {
            SavedMealPickerView(mealSlotName: slot.name) { items in
                Task { await viewModel.applySavedMeal(items, mealSlotId: slot.id, date: date) }
            }
        }
        .sheet(isPresented: $isSavingMeal) {
            SaveMealSheet(entries: viewModel.entries(forSlot: slot.id)) {}
        }
    }

    private func quantityLabel(_ quantity: Double) -> String {
        quantity == quantity.rounded() ? "\(Int(quantity))" : String(format: "%.1f", quantity)
    }

    private func macroText(_ label: String, _ grams: Double) -> some View {
        HStack(spacing: 3) {
            Text(label).fontWeight(.bold)
            Text("\(Int(grams))g")
        }
    }
}
