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
    @State private var addingMealPrep = false
    @State private var addingSavedMeal = false
    @State private var isSavingMeal = false
    @State private var editingEntry: MealSlotEntry?

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
                    Button {
                        editingEntry = slotEntry
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(slotEntry.name)
                                    .foregroundStyle(.primary)
                                Text("\(quantityLabel(slotEntry.entry.quantity)) \u{00d7} \(slotEntry.servingLabel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(Int(slotEntry.calories)) kcal")
                                .foregroundStyle(.secondary)
                        }
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
                        addingMealPrep = true
                    } label: {
                        Label("Log Meal Prep", systemImage: "takeoutbag.and.cup.and.straw")
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
        .sheet(isPresented: $addingMealPrep) {
            MealPrepPickerView(slot: slot, date: date) { summary, quantity in
                Task { await viewModel.logRecipe(summary.recipe, quantity: quantity, mealSlotId: slot.id, date: date) }
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
        .sheet(item: $editingEntry) { slotEntry in
            EditMealEntryQuantityView(entry: slotEntry) { newQuantity in
                Task { await viewModel.updateQuantity(slotEntry.entry, quantity: newQuantity) }
            }
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

/// The per-serving numbers `EditMealEntryQuantityView` needs, pulled from
/// whichever of `MealSlotEntry.food`/`.recipe` is set - both types already
/// expose the same per-serving shape (`servingSize`/`servingUnit`, plain
/// per-serving calories/macros), just as two different Swift types, so this
/// flattens them into one the view can work with generically.
private struct EditableFoodInfo {
    let name: String
    let servingSize: Double
    let servingUnit: String
    let caloriesPerUnit: Double
    let proteinPerUnit: Double
    let carbsPerUnit: Double
    let fatPerUnit: Double
    let fiberPerUnit: Double?

    init?(_ entry: MealSlotEntry) {
        if let food = entry.food {
            name = food.displayName
            servingSize = food.servingSize
            servingUnit = food.servingUnit
            caloriesPerUnit = food.calories
            proteinPerUnit = food.proteinG
            carbsPerUnit = food.carbsG
            fatPerUnit = food.fatG
            fiberPerUnit = food.fiberG
        } else if let recipe = entry.recipe {
            name = recipe.name
            servingSize = recipe.servingSize
            servingUnit = recipe.servingUnit
            caloriesPerUnit = recipe.calories
            proteinPerUnit = recipe.proteinG
            carbsPerUnit = recipe.carbsG
            fatPerUnit = recipe.fatG
            fiberPerUnit = recipe.fiberG
        } else {
            return nil
        }
    }
}

/// Reopens the same Servings/Amount editor + macro ring
/// `LogFoodQuantityView` (`FoodPickerView.swift`) uses when first logging a
/// food, pre-filled with what's already logged, saving back onto the
/// existing entry instead of creating a new one - what tapping a row in
/// `MealSlotDetailView` opens.
private struct EditMealEntryQuantityView: View {
    let entry: MealSlotEntry
    let onConfirm: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var quantityText: String
    @State private var inputMode: QuantityInputMode = .servings
    private let info: EditableFoodInfo?

    init(entry: MealSlotEntry, onConfirm: @escaping (Double) -> Void) {
        self.entry = entry
        self.onConfirm = onConfirm
        self.info = EditableFoodInfo(entry)
        _quantityText = State(initialValue: Self.formattedQuantity(entry.entry.quantity))
    }

    private var quantity: Double? {
        guard let entered = Double(quantityText), let info else { return nil }
        switch inputMode {
        case .servings: return entered
        case .amount: return info.servingSize > 0 ? entered / info.servingSize : nil
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let info {
                    Section {
                        Picker("Enter as", selection: $inputMode) {
                            Text("Servings").tag(QuantityInputMode.servings)
                            Text(info.servingUnit.capitalized).tag(QuantityInputMode.amount)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: inputMode) { oldMode, newMode in
                            convertQuantityText(from: oldMode, to: newMode, servingSize: info.servingSize)
                        }
                        HStack {
                            Text(inputMode == .servings ? "Servings" : "Amount")
                            Spacer()
                            TextField("1", text: $quantityText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 70)
                            Text(inputMode == .servings ? "\u{00d7} \(servingLabel(info))" : info.servingUnit)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let quantity, quantity > 0 {
                        Section {
                            MacroBreakdownRing(
                                calories: info.caloriesPerUnit * quantity,
                                carbsG: info.carbsPerUnit * quantity,
                                fatG: info.fatPerUnit * quantity,
                                proteinG: info.proteinPerUnit * quantity
                            )
                            .padding(.vertical, 8)
                        }
                        Section("Adds") {
                            LabeledContent("Calories", value: "\(Int(info.caloriesPerUnit * quantity)) kcal")
                            LabeledContent("Protein", value: "\(Int(info.proteinPerUnit * quantity))g")
                            LabeledContent("Carbs", value: "\(Int(info.carbsPerUnit * quantity))g")
                            LabeledContent("Fat", value: "\(Int(info.fatPerUnit * quantity))g")
                            if let fiberPerUnit = info.fiberPerUnit {
                                LabeledContent("Fiber", value: "\(Int(fiberPerUnit * quantity))g")
                            }
                        }
                    }
                }
            }
            .navigationTitle(info?.name ?? entry.name)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        if let quantity {
                            onConfirm(quantity)
                            dismiss()
                        }
                    }
                    .disabled(!(quantity.map { $0 > 0 } ?? false))
                }
            }
        }
    }

    private func convertQuantityText(from oldMode: QuantityInputMode, to newMode: QuantityInputMode, servingSize: Double) {
        guard oldMode != newMode, let entered = Double(quantityText), servingSize > 0 else { return }
        switch newMode {
        case .servings: quantityText = Self.formattedQuantity(entered / servingSize)
        case .amount: quantityText = Self.formattedQuantity(entered * servingSize)
        }
    }

    private func servingLabel(_ info: EditableFoodInfo) -> String {
        let sizeText = info.servingSize == info.servingSize.rounded() ? "\(Int(info.servingSize))" : String(format: "%.1f", info.servingSize)
        return "\(sizeText)\(info.servingUnit)"
    }

    private static func formattedQuantity(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}
