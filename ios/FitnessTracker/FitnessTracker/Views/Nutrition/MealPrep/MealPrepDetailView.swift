import SwiftUI

/// One batch: what's in it, what's left, and what changed since the last
/// time this was made. The "what changed" part is the point of treating a
/// prep as a snapshot - same overnight oats, different yoghurt - and it
/// leans on the user's brand links (`FoodGroupRepository`) to describe a
/// changed ingredient as a swap rather than an unrelated drop and add.
struct MealPrepDetailView: View {
    private enum IngredientChange: Identifiable {
        case swapped(old: Food, new: Food)
        case added(Food)
        case dropped(Food)
        case reweighed(Food, oldAmount: Double, newAmount: Double)

        var id: String {
            switch self {
            case let .swapped(old, new): return "swap-\(old.id)-\(new.id)"
            case let .added(food): return "add-\(food.id)"
            case let .dropped(food): return "drop-\(food.id)"
            case let .reweighed(food, _, _): return "weigh-\(food.id)"
            }
        }
    }

    let previous: MealPrepSummary?
    let onChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var summary: MealPrepSummary
    @State private var ingredients: [PrepIngredient] = []
    @State private var changes: [IngredientChange] = []
    @State private var showingLogSheet = false
    @State private var prepAgainPrefill: MealPrepBuilderView.Prefill?
    @State private var confirmingDelete = false
    @State private var editingBatch = false
    @State private var errorMessage: String?
    private let repository = MealPrepRepository()
    private let groupRepository = FoodGroupRepository()

    init(summary: MealPrepSummary, previous: MealPrepSummary?, onChange: @escaping () -> Void) {
        _summary = State(initialValue: summary)
        self.previous = previous
        self.onChange = onChange
    }

    var body: some View {
        List {
            Section {
                MacroBreakdownRing(
                    calories: summary.recipe.calories,
                    carbsG: summary.recipe.carbsG,
                    fatG: summary.recipe.fatG,
                    proteinG: summary.recipe.proteinG
                )
                .padding(.vertical, 8)
                LabeledContent("Per portion", value: "\(Int(summary.recipe.calories)) kcal")
                LabeledContent("Left", value: "\(MealPrepCalculator.label(summary.remainingPortions)) of \(MealPrepCalculator.label(summary.prep.portions))")
                LabeledContent("Made", value: summary.prep.preppedDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                if summary.prep.isFrozen {
                    HStack {
                        Text("Stored")
                        Spacer()
                        Image(systemName: "snowflake")
                        Text("Freezer")
                    }
                    .foregroundStyle(.cyan)
                    if let frozenDate = summary.prep.frozenDate {
                        LabeledContent("Frozen", value: frozenDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    }
                } else {
                    LabeledContent("Eat by", value: summary.prep.eatBy.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                }
                if let weight = summary.prep.portionWeightG {
                    LabeledContent("Portion weight", value: "\(Int(weight.rounded()))g")
                }
            }

            if !summary.isFinished {
                Section {
                    Button {
                        showingLogSheet = true
                    } label: {
                        Label("Log a Portion", systemImage: "fork.knife")
                    }
                }
            }

            Section("Ingredients") {
                if ingredients.isEmpty {
                    Text("Loading...").foregroundStyle(.secondary)
                }
                ForEach(ingredients) { ingredient in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ingredient.food.displayName)
                            Text(amountLabel(ingredient))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(ingredient.food.calories(at: ingredient.quantity))) kcal")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let previous {
                Section {
                    deltaRow("Calories", new: summary.recipe.calories, old: previous.recipe.calories, unit: " kcal")
                    deltaRow("Protein", new: summary.recipe.proteinG, old: previous.recipe.proteinG, unit: "g")
                    deltaRow("Carbs", new: summary.recipe.carbsG, old: previous.recipe.carbsG, unit: "g")
                    deltaRow("Fat", new: summary.recipe.fatG, old: previous.recipe.fatG, unit: "g")
                    ForEach(changes) { change in
                        changeRow(change)
                    }
                } header: {
                    Text("Vs batch of \(previous.prep.preppedDate.formatted(.dateTime.day().month(.abbreviated)))")
                } footer: {
                    Text("Per portion.")
                }
            }

            Section {
                Button {
                    editingBatch = true
                } label: {
                    Label("Edit Batch", systemImage: "slider.horizontal.3")
                }

                Button {
                    prepAgainPrefill = MealPrepBuilderView.Prefill(
                        name: summary.prep.name,
                        portions: summary.prep.portions,
                        eatWithinDays: summary.prep.eatWithinDays,
                        ingredients: ingredients
                    )
                } label: {
                    Label("Make Again", systemImage: "arrow.clockwise")
                }
                .disabled(ingredients.isEmpty)

                if !summary.isFinished {
                    if summary.prep.isFrozen {
                        Button {
                            Task { await move(toFreezer: false) }
                        } label: {
                            Label("Move to Fridge", systemImage: "refrigerator")
                        }
                    } else {
                        Button {
                            Task { await move(toFreezer: true) }
                        } label: {
                            Label("Move to Freezer", systemImage: "snowflake")
                        }
                    }
                    Button {
                        Task { await finish() }
                    } label: {
                        Label("Mark as Finished", systemImage: "checkmark.circle")
                    }
                }

                if summary.eatenPortions == 0 {
                    Button(role: .destructive) {
                        confirmingDelete = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            } footer: {
                if summary.prep.isFrozen {
                    Text("Frozen batches don't count down. Moving it back to the fridge restarts the \(summary.prep.eatWithinDays)-day eat-by clock from today.")
                } else if summary.eatenPortions > 0 {
                    Text("Eaten from, so it can be finished but not deleted - the portions you logged still count in your totals.")
                }
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .navigationTitle(summary.prep.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadIngredients() }
        .sheet(isPresented: $showingLogSheet) {
            LogPrepPortionView(summary: summary, fixedSlot: nil, fixedDate: nil) { quantity, slot, date in
                Task { await logPortion(quantity: quantity, slot: slot, date: date) }
            }
        }
        .sheet(isPresented: $editingBatch) {
            EditBatchSheet(summary: summary) {
                Task {
                    await refreshSummary()
                    onChange()
                }
            }
        }
        .sheet(item: $prepAgainPrefill) { prefill in
            MealPrepBuilderView(prefill: prefill) { _ in
                onChange()
                dismiss()
            }
        }
        .confirmationDialog("Delete this batch?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await delete() } }
        }
    }

    // MARK: - Rows

    private func amountLabel(_ ingredient: PrepIngredient) -> String {
        let food = ingredient.food
        let unit = food.servingUnit.lowercased()
        if unit == "g" || unit == "ml" {
            return formatted(ingredient.amount) + food.servingUnit
        }
        return formatted(ingredient.quantity) + " \u{00d7} " + food.servingLabel
    }

    private func formatted(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }

    private func deltaRow(_ label: String, new: Double, old: Double, unit: String) -> some View {
        let rounded = Int((new - old).rounded())
        return LabeledContent(label) {
            Text(rounded == 0 ? "same" : "\(rounded > 0 ? "+" : "")\(rounded)\(unit)")
                .foregroundStyle(rounded == 0 ? Color.secondary : Color.primary)
        }
    }

    @ViewBuilder
    private func changeRow(_ change: IngredientChange) -> some View {
        switch change {
        case let .swapped(old, new):
            Label {
                Text("\(old.displayName) \u{2192} \(new.displayName)")
            } icon: {
                Image(systemName: "arrow.left.arrow.right").foregroundStyle(.blue)
            }
            .font(.subheadline)
        case let .added(food):
            Label("Added \(food.displayName)", systemImage: "plus.circle")
                .font(.subheadline)
        case let .dropped(food):
            Label("Dropped \(food.displayName)", systemImage: "minus.circle")
                .font(.subheadline)
        case let .reweighed(food, oldAmount, newAmount):
            Label("\(food.name): \(formatted(oldAmount)) \u{2192} \(formatted(newAmount))\(food.servingUnit)", systemImage: "scalemass")
                .font(.subheadline)
        }
    }

    // MARK: - Actions

    private func loadIngredients() async {
        do {
            ingredients = try await repository.fetchIngredients(of: summary.prep)
            if let previous {
                let previousIngredients = try await repository.fetchIngredients(of: previous.prep)
                let groups = (try? await groupRepository.fetchSummaries()) ?? []
                changes = diff(current: ingredients, previous: previousIngredients, groups: groups)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Pairs a food that left with a food that arrived when both belong to
    /// the same brand group (a swap); whatever can't be paired is a plain
    /// add or drop. Foods present in both batches only show up if their
    /// weight moved by more than a couple of percent.
    private func diff(current: [PrepIngredient], previous: [PrepIngredient], groups: [FoodGroupSummary]) -> [IngredientChange] {
        var groupOfFood: [UUID: UUID] = [:]
        for group in groups {
            for food in group.foods { groupOfFood[food.id] = group.id }
        }
        let previousById = Dictionary(previous.map { ($0.food.id, $0) }, uniquingKeysWith: { first, _ in first })
        let currentIds = Set(current.map(\.food.id))

        var result: [IngredientChange] = []
        var dropped = previous.filter { !currentIds.contains($0.food.id) }.map(\.food)
        var added = current.filter { previousById[$0.food.id] == nil }.map(\.food)

        for old in dropped {
            guard let groupId = groupOfFood[old.id],
                  let matchIndex = added.firstIndex(where: { groupOfFood[$0.id] == groupId })
            else { continue }
            result.append(.swapped(old: old, new: added[matchIndex]))
            added.remove(at: matchIndex)
            dropped.removeAll { $0.id == old.id }
        }
        result += dropped.map { .dropped($0) }
        result += added.map { .added($0) }

        for ingredient in current {
            guard let old = previousById[ingredient.food.id], old.amount > 0 else { continue }
            if abs(ingredient.amount - old.amount) / old.amount > 0.02 {
                result.append(.reweighed(ingredient.food, oldAmount: old.amount, newAmount: ingredient.amount))
            }
        }
        return result
    }

    private func logPortion(quantity: Double, slot: MealSlot, date: Date) async {
        do {
            try OfflineMealQueue.shared.addRecipeEntry(date: date, mealSlotId: slot.id, recipeId: summary.recipe.id, quantity: quantity)
            await refreshSummary()
            onChange()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func move(toFreezer: Bool) async {
        do {
            if toFreezer {
                try await repository.freeze(id: summary.prep.id)
            } else {
                try await repository.thaw(id: summary.prep.id)
            }
            await refreshSummary()
            onChange()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finish() async {
        do {
            try await repository.markFinished(id: summary.prep.id)
            await refreshSummary()
            onChange()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() async {
        do {
            try await repository.delete(summary.prep)
            onChange()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshSummary() async {
        if let updated = try? await repository.fetchSummaries().first(where: { $0.id == summary.id }) {
            summary = updated
        }
    }
}

extension MealPrepBuilderView.Prefill: Identifiable {
    var id: String { name + String(ingredients.count) }
}

/// Change how a batch is split: portions, how long it keeps, cooked weight.
/// Portions are locked once any have been eaten - they set what one portion
/// is worth, which would quietly rewrite what's already been logged.
private struct EditBatchSheet: View {
    let summary: MealPrepSummary
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var portions: Int
    @State private var eatWithinDays: Int
    @State private var weightText: String
    @State private var errorMessage: String?
    @State private var isSaving = false
    private let repository = MealPrepRepository()

    init(summary: MealPrepSummary, onSaved: @escaping () -> Void) {
        self.summary = summary
        self.onSaved = onSaved
        _portions = State(initialValue: max(1, Int(summary.prep.portions.rounded())))
        _eatWithinDays = State(initialValue: summary.prep.eatWithinDays)
        _weightText = State(initialValue: summary.prep.totalWeightG.map { $0 == $0.rounded() ? "\(Int($0))" : String(format: "%.1f", $0) } ?? "")
    }

    private var portionsLocked: Bool { summary.eatenPortions > 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("Makes \(portions) portion\(portions == 1 ? "" : "s")", value: $portions, in: 1...50)
                        .disabled(portionsLocked)
                    Stepper("Eat within \(eatWithinDays) day\(eatWithinDays == 1 ? "" : "s")", value: $eatWithinDays, in: 1...14)
                    HStack {
                        Text("Cooked weight")
                        Spacer()
                        TextField("optional", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                        Text("g").foregroundStyle(.secondary)
                    }
                } footer: {
                    if portionsLocked {
                        Text("Portions are locked - you've already eaten from this batch, and changing them would change what those logged portions are worth.")
                    } else {
                        Text("Portions set what one serving is worth: the whole batch divided by this.")
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Edit Batch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .disabled(isSaving)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let weight = Double(weightText).flatMap { $0 > 0 ? $0 : nil }
        do {
            try await repository.update(
                prep: summary.prep,
                portions: portionsLocked ? summary.prep.portions : Double(portions),
                eatWithinDays: eatWithinDays,
                totalWeightG: weight
            )
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
