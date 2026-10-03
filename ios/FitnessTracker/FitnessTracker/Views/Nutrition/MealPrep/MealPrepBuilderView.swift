import SwiftUI

/// Builds one batch: name, ingredients weighed separately, how many
/// portions it makes and how long it keeps. Each save is a fresh snapshot -
/// "Prep again" (see `MealPrepDetailView`) pre-fills this screen from an
/// older batch, and swapping an ingredient's brand here is also how two
/// foods get linked as the same product (`FoodGroupRepository.link`), which
/// is what powers the "better macros" hints below and Brand Compare.
struct MealPrepBuilderView: View {
    struct Prefill {
        let name: String
        let portions: Double
        let eatWithinDays: Int
        let ingredients: [PrepIngredient]
    }

    let prefill: Prefill?
    let onSaved: (MealPrep) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var preppedOn = Date()
    @State private var portions = 4
    @State private var eatWithinDays = 3
    @State private var totalWeightText = ""
    @State private var ingredients: [PrepIngredient] = []
    @State private var showingAddIngredient = false
    @State private var editingIngredient: PrepIngredient?
    @State private var swappingIngredient: PrepIngredient?
    @State private var isSaving = false
    @State private var errorMessage: String?
    /// Every group the user has, keyed by each member food - looked up per
    /// ingredient to find linked brands without a query per row.
    @State private var groupsByFood: [UUID: FoodGroupSummary] = [:]
    @State private var previousBatch: MealPrepSummary?
    private let repository = MealPrepRepository()
    private let groupRepository = FoodGroupRepository()

    init(prefill: Prefill? = nil, onSaved: @escaping (MealPrep) -> Void) {
        self.prefill = prefill
        self.onSaved = onSaved
    }

    private var batchTotals: DayMacroTotals {
        RecipeRepository.totals(for: ingredients.map { ($0.food, $0.quantity) })
    }

    private var perPortion: DayMacroTotals {
        MealPrepCalculator.perPortion(batchTotals, portions: Double(portions))
    }

    private var totalWeightG: Double? {
        guard let weight = Double(totalWeightText), weight > 0 else { return nil }
        return weight
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !ingredients.isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Batch") {
                    TextField("Name (e.g. Overnight oats)", text: $name)
                    DatePicker("Made on", selection: $preppedOn, displayedComponents: .date)
                    Stepper("Makes \(portions) portion\(portions == 1 ? "" : "s")", value: $portions, in: 1...30)
                    Stepper("Eat within \(eatWithinDays) day\(eatWithinDays == 1 ? "" : "s")", value: $eatWithinDays, in: 1...14)
                    HStack {
                        Text("Cooked weight")
                        Spacer()
                        TextField("optional", text: $totalWeightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("g").foregroundStyle(.secondary)
                    }
                }

                Section {
                    ForEach(ingredients) { ingredient in
                        ingredientRow(ingredient)
                    }
                    Button {
                        showingAddIngredient = true
                    } label: {
                        Label("Add Ingredient", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Ingredients")
                } footer: {
                    Text("Weigh each one as it goes in. Tap an amount to change it, or use ... to swap in a different brand.")
                }

                if !ingredients.isEmpty {
                    Section("Per portion") {
                        MacroBreakdownRing(
                            calories: perPortion.calories,
                            carbsG: perPortion.carbsG,
                            fatG: perPortion.fatG,
                            proteinG: perPortion.proteinG
                        )
                        .padding(.vertical, 8)
                        LabeledContent("Calories", value: "\(Int(perPortion.calories)) kcal")
                        LabeledContent("Protein", value: "\(Int(perPortion.proteinG))g")
                        LabeledContent("Carbs", value: "\(Int(perPortion.carbsG))g")
                        LabeledContent("Fat", value: "\(Int(perPortion.fatG))g")
                        LabeledContent("Whole batch", value: "\(Int(batchTotals.calories)) kcal")
                    }

                    if let previousBatch {
                        Section("Vs last batch") {
                            batchComparison(previousBatch)
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("New Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
            .task {
                applyPrefillIfNeeded()
                await loadGroups()
            }
            // Re-resolved as the name settles (and cancelled by the next
            // keystroke) rather than refetching every prep per character.
            .task(id: name) {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }
                await loadPreviousBatch()
            }
            .sheet(isPresented: $showingAddIngredient) {
                FoodPickerView(mealSlotName: "Recipe") { food, quantity in
                    ingredients.append(PrepIngredient(food: food, quantity: quantity))
                }
            }
            .sheet(item: $editingIngredient) { ingredient in
                IngredientAmountSheet(ingredient: ingredient) { quantity in
                    replace(ingredient, with: PrepIngredient(food: ingredient.food, quantity: quantity))
                }
            }
            .sheet(item: $swappingIngredient) { ingredient in
                BrandSwapSheet(
                    ingredient: ingredient,
                    linkedFoods: groupsByFood[ingredient.food.id]?.foods.filter { $0.id != ingredient.food.id } ?? []
                ) { newFood, pickedQuantity in
                    swap(ingredient, to: newFood, pickedQuantity: pickedQuantity)
                }
            }
        }
    }

    // MARK: - Rows

    private func ingredientRow(_ ingredient: PrepIngredient) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ingredient.food.displayName)
                Text(amountLabel(ingredient))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let hint = betterBrandHint(for: ingredient.food) {
                    Label(hint, systemImage: "arrow.up.right.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { editingIngredient = ingredient }
            Spacer()
            Text("\(Int(ingredient.food.calories(at: ingredient.quantity))) kcal")
                .foregroundStyle(.secondary)
            Menu {
                Button {
                    editingIngredient = ingredient
                } label: {
                    Label("Change Amount", systemImage: "scalemass")
                }
                Button {
                    swappingIngredient = ingredient
                } label: {
                    Label("Swap Brand", systemImage: "arrow.left.arrow.right")
                }
                Button(role: .destructive) {
                    ingredients.removeAll { $0.id == ingredient.id }
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
    }

    /// "250g" for a weighed food, "2 \u{00d7} 1 bar" for anything measured in pieces.
    private func amountLabel(_ ingredient: PrepIngredient) -> String {
        let food = ingredient.food
        let unit = food.servingUnit.lowercased()
        if unit == "g" || unit == "ml" {
            let amount = ingredient.amount
            return (amount == amount.rounded() ? "\(Int(amount))" : String(format: "%.1f", amount)) + food.servingUnit
        }
        let quantity = ingredient.quantity
        return (quantity == quantity.rounded() ? "\(Int(quantity))" : String(format: "%.1f", quantity)) + " \u{00d7} " + food.servingLabel
    }

    /// If a brand this user has linked to this food packs more protein per
    /// calorie, say so right where the ingredient is being chosen.
    private func betterBrandHint(for food: Food) -> String? {
        guard let summary = groupsByFood[food.id],
              let current = FoodComparator.per100(food),
              let best = FoodComparator.ranked(summary.foods, by: .proteinPerKcal).first,
              best.food.id != food.id,
              best.proteinPer100Kcal - current.proteinPer100Kcal >= 0.5
        else { return nil }
        return String(format: "%@ has %.1fg more protein per 100 kcal", best.food.displayName, best.proteinPer100Kcal - current.proteinPer100Kcal)
    }

    private func batchComparison(_ previous: MealPrepSummary) -> some View {
        let old = previous.recipe
        return Group {
            deltaRow("Calories", new: perPortion.calories, old: old.calories, unit: " kcal")
            deltaRow("Protein", new: perPortion.proteinG, old: old.proteinG, unit: "g")
            deltaRow("Carbs", new: perPortion.carbsG, old: old.carbsG, unit: "g")
            deltaRow("Fat", new: perPortion.fatG, old: old.fatG, unit: "g")
        }
    }

    private func deltaRow(_ label: String, new: Double, old: Double, unit: String) -> some View {
        let delta = new - old
        let rounded = Int(delta.rounded())
        return LabeledContent(label) {
            Text(rounded == 0 ? "same" : "\(rounded > 0 ? "+" : "")\(rounded)\(unit)")
                .foregroundStyle(rounded == 0 ? Color.secondary : Color.primary)
        }
    }

    // MARK: - Changes

    private func replace(_ old: PrepIngredient, with new: PrepIngredient) {
        guard let index = ingredients.firstIndex(where: { $0.id == old.id }) else { return }
        ingredients[index] = new
    }

    /// Keeps the same weight going in when both foods are measured in the
    /// same unit (the whole point of swapping a brand - same recipe, same
    /// grams); otherwise falls back to whatever was entered for the new
    /// food. Either way the two are linked as one product.
    private func swap(_ old: PrepIngredient, to newFood: Food, pickedQuantity: Double?) {
        let sameUnit = old.food.servingUnit.lowercased() == newFood.servingUnit.lowercased()
        let quantity: Double
        if sameUnit, newFood.servingSize > 0 {
            quantity = old.amount / newFood.servingSize
        } else {
            quantity = pickedQuantity ?? 1
        }
        replace(old, with: PrepIngredient(food: newFood, quantity: quantity))
        Task {
            _ = try? await groupRepository.link(old.food, newFood)
            await loadGroups()
        }
    }

    // MARK: - Loading

    private func applyPrefillIfNeeded() {
        guard let prefill, ingredients.isEmpty, name.isEmpty else { return }
        name = prefill.name
        portions = max(1, Int(prefill.portions.rounded()))
        eatWithinDays = prefill.eatWithinDays
        ingredients = prefill.ingredients
    }

    private func loadGroups() async {
        guard let summaries = try? await groupRepository.fetchSummaries() else { return }
        var byFood: [UUID: FoodGroupSummary] = [:]
        for summary in summaries {
            for food in summary.foods { byFood[food.id] = summary }
        }
        groupsByFood = byFood
    }

    /// The most recent earlier batch with the same name - what "vs last
    /// batch" compares against, so a swapped brand's effect on one portion
    /// is visible before saving.
    private func loadPreviousBatch() async {
        let trimmed = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty, let summaries = try? await repository.fetchSummaries() else {
            previousBatch = nil
            return
        }
        previousBatch = summaries.first { $0.prep.name.lowercased() == trimmed }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let prep = try await repository.create(
                name: name.trimmingCharacters(in: .whitespaces),
                preppedOn: preppedOn,
                portions: Double(portions),
                eatWithinDays: eatWithinDays,
                totalWeightG: totalWeightG,
                ingredients: ingredients
            )
            onSaved(prep)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Edit one ingredient's weight, in the food's own unit - the same "type
/// the grams" shape `FoodPickerView`'s quantity step uses, without the
/// meal-slot context.
private struct IngredientAmountSheet: View {
    let ingredient: PrepIngredient
    let onConfirm: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText: String

    init(ingredient: PrepIngredient, onConfirm: @escaping (Double) -> Void) {
        self.ingredient = ingredient
        self.onConfirm = onConfirm
        let amount = ingredient.amount
        _amountText = State(initialValue: amount == amount.rounded() ? "\(Int(amount))" : String(format: "%.1f", amount))
    }

    private var quantity: Double? {
        guard let amount = Double(amountText), amount > 0, ingredient.food.servingSize > 0 else { return nil }
        return amount / ingredient.food.servingSize
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("0", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text(ingredient.food.servingUnit).foregroundStyle(.secondary)
                    }
                }
                if let quantity {
                    Section("Adds") {
                        LabeledContent("Calories", value: "\(Int(ingredient.food.calories(at: quantity))) kcal")
                        LabeledContent("Protein", value: "\(Int(ingredient.food.proteinG(at: quantity)))g")
                        LabeledContent("Carbs", value: "\(Int(ingredient.food.carbsG(at: quantity)))g")
                        LabeledContent("Fat", value: "\(Int(ingredient.food.fatG(at: quantity)))g")
                    }
                }
            }
            .navigationTitle(ingredient.food.name)
            .navigationBarTitleDisplayMode(.inline)
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
                    .disabled(quantity == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Pick a different brand for an ingredient - the brands already linked to
/// it come first, each with how its macros compare per 100g, then a search
/// for one that isn't linked yet (which links it on the way out).
private struct BrandSwapSheet: View {
    let ingredient: PrepIngredient
    let linkedFoods: [Food]
    /// `pickedQuantity` is only set when the food came from search (whose
    /// quantity step already asked for an amount); linked brands swap in at
    /// the current weight instead.
    let onSwap: (Food, Double?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showingSearch = false

    private var current: FoodPer100? { FoodComparator.per100(ingredient.food) }

    var body: some View {
        NavigationStack {
            List {
                Section("Now") {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ingredient.food.displayName)
                        if let current {
                            Text(macroLine(current))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !linkedFoods.isEmpty {
                    Section("Your other brands") {
                        ForEach(FoodComparator.ranked(linkedFoods, by: .proteinPerKcal), id: \.food.id) { item in
                            Button {
                                onSwap(item.food, nil)
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.food.displayName).foregroundStyle(.primary)
                                        Text(macroLine(item))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if let current {
                                        Text(deltaLabel(item, versus: current))
                                            .font(.caption.bold())
                                            .foregroundStyle(item.proteinPer100Kcal >= current.proteinPer100Kcal ? .green : .orange)
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    Button {
                        showingSearch = true
                    } label: {
                        Label("Find Another Brand", systemImage: "magnifyingglass")
                    }
                } footer: {
                    Text("Swapping links the two as the same product, so Brand Compare can rank them.")
                }
            }
            .navigationTitle("Swap Brand")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingSearch) {
                FoodPickerView(mealSlotName: "Recipe") { food, quantity in
                    onSwap(food, quantity)
                    dismiss()
                }
            }
        }
    }

    private func macroLine(_ item: FoodPer100) -> String {
        String(format: "per 100g: %d kcal \u{00b7} P %.1f \u{00b7} C %.1f \u{00b7} F %.1f", Int(item.calories.rounded()), item.proteinG, item.carbsG, item.fatG)
    }

    private func deltaLabel(_ item: FoodPer100, versus current: FoodPer100) -> String {
        let delta = item.proteinPer100Kcal - current.proteinPer100Kcal
        if abs(delta) < 0.05 { return "same protein/kcal" }
        return String(format: "%@%.1fg P/100kcal", delta > 0 ? "+" : "", delta)
    }
}
