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
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                optionsRow

                if entries.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 10) {
                        ForEach(entries) { slotEntry in
                            foodCard(slotEntry)
                        }
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .navigationTitle(slot.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $addingFood) {
            FoodPickerView(mealSlotName: slot.name) { food, quantity in
                Task { await viewModel.logFood(food, quantity: quantity, mealSlotId: slot.id, date: date) }
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


    // MARK: - Header

    /// The meal's totals up top - calories and the carbs/fat/protein split -
    /// so the whole meal reads at a glance before the individual foods.
    private var headerCard: some View {
        let calories = group?.totalCalories ?? 0
        let carbs = group?.totalCarbsG ?? 0
        let fat = group?.totalFatG ?? 0
        let protein = group?.totalProteinG ?? 0
        return VStack(spacing: 14) {
            HStack(spacing: 18) {
                MacroRing(calories: calories, carbsG: carbs, fatG: fat, proteinG: protein)
                    .frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 8) {
                    macroLine("Protein", protein, color: .blue)
                    macroLine("Carbs", carbs, color: .green)
                    macroLine("Fat", fat, color: .yellow)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    private func macroLine(_ label: String, _ grams: Double, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text("\(Int(grams.rounded()))g")
                .font(.subheadline.bold())
                .monospacedDigit()
        }
    }

    // MARK: - Options

    /// What you can do with this meal, as buttons in reach rather than
    /// tucked behind a top-corner menu.
    private var optionsRow: some View {
        HStack(spacing: 10) {
            optionButton("Add Food", icon: "plus") { addingFood = true }
            optionButton("Recipes", icon: "takeoutbag.and.cup.and.straw") { addingMealPrep = true }
            optionButton("Saved", icon: "list.bullet.rectangle") { addingSavedMeal = true }
            if !entries.isEmpty {
                optionButton("Save Meal", icon: "bookmark") { isSavingMeal = true }
            }
        }
    }

    private func optionButton(_ label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(height: 24)
                Text(label)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.blue)
    }

    // MARK: - Foods

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "fork.knife")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Nothing logged for \(slot.name) yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    /// One food: name (with its brand underneath), the amount eaten and its
    /// calories, then protein/carbs/fat for just that item.
    private func foodCard(_ slotEntry: MealSlotEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(slotEntry.title)
                        .font(.body.weight(.semibold))
                    if slotEntry.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
                if let brand = slotEntry.brand {
                    Text(brand)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(slotEntry.amountLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    macroPill("P", slotEntry.proteinG, .blue)
                    macroPill("C", slotEntry.carbsG, .green)
                    macroPill("F", slotEntry.fatG, .yellow)
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 8) {
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int(slotEntry.calories.rounded()))")
                        .font(.title3.bold())
                        .monospacedDigit()
                    Text("kcal")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Menu {
                    Button {
                        editingEntry = slotEntry
                    } label: {
                        Label("Edit Amount", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        Task { await viewModel.deleteEntry(slotEntry.entry) }
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 28)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { editingEntry = slotEntry }
    }

    private func macroPill(_ label: String, _ grams: Double, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(label) \(Int(grams.rounded()))g")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

/// Calories at the centre, ringed by carbs/fat/protein's share of them
/// (4/9/4 kcal per gram) - the same idea as `MacroBreakdownRing`, sized for
/// the meal header and without its legend, since the header lists the
/// macros beside it.
private struct MacroRing: View {
    let calories: Double
    let carbsG: Double
    let fatG: Double
    let proteinG: Double

    private var segments: [(Color, Double)] {
        let carbs = carbsG * 4, fat = fatG * 9, protein = proteinG * 4
        let total = carbs + fat + protein
        guard total > 0 else { return [] }
        return [(.green, carbs / total), (.yellow, fat / total), (.blue, protein / total)]
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.secondary.opacity(0.18), lineWidth: 11)
            ForEach(Array(arcs.enumerated()), id: \.offset) { _, arc in
                Circle()
                    .trim(from: arc.start, to: arc.end)
                    .stroke(arc.color, style: StrokeStyle(lineWidth: 11, lineCap: .butt))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text("\(Int(calories.rounded()))")
                    .font(.title2.bold())
                    .monospacedDigit()
                Text("kcal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var arcs: [(color: Color, start: Double, end: Double)] {
        var start = 0.0
        return segments.map { color, share in
            defer { start += share }
            return (color, start, start + share)
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
