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
    /// Carbs to aim for in this meal - set for the Preworkout slot only.
    var preworkoutCarbTargetG: Double?

    @State private var addingFood = false
    @State private var addingSavedMeal = false
    @State private var copyingMeal = false
    @State private var weighing = false
    @State private var isSavingMeal = false
    @State private var editingEntry: MealSlotEntry?

    private var group: MealSlotGroup? {
        viewModel.slotGroups.first { $0.slot.id == slot.id }
    }

    private var entries: [MealSlotEntry] {
        group?.entries ?? []
    }

    /// The meal read as its protein / carb / fat parts - chicken, rice and
    /// avocado land under Protein, Carbs and Fat - in that order, each with
    /// its foods. A food listed under several categories (salmon: protein and
    /// fat) sits under its main one.
    private var categoryParts: [(category: FoodCategory, items: [MealSlotEntry])] {
        let byCategory = Dictionary(grouping: entries, by: \.category)
        return FoodCategory.allCases
            .sorted { $0.sortOrder < $1.sortOrder }
            .compactMap { category in
                byCategory[category].map { (category, $0) }
            }
    }

    /// A part's heading: its name, and what it adds up to.
    private func partHeader(_ category: FoodCategory, _ items: [MealSlotEntry]) -> some View {
        let kcal = items.reduce(0) { $0 + $1.calories }
        let grams: Double? = switch category {
        case .protein: items.reduce(0) { $0 + $1.proteinG }
        case .carb: items.reduce(0) { $0 + $1.carbsG }
        case .fat: items.reduce(0) { $0 + $1.fatG }
        case .other: nil
        }
        let color: Color = switch category {
        case .protein: AppColor.protein
        case .carb: AppColor.carbs
        case .fat: AppColor.fat
        case .other: Color.secondary
        }
        return HStack(spacing: 8) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(category.displayName)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(grams.map { "\(Int($0.rounded()))g \u{00b7} \(Int(kcal.rounded())) kcal" } ?? "\(Int(kcal.rounded())) kcal")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 4)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                if let target = preworkoutCarbTargetG, slot.isPreworkout {
                    PreworkoutCarbCard(carbsG: group?.totalCarbsG ?? 0, targetG: target, slotName: slot.name, mealSlotId: slot.id, date: date) { food, servings in
                        Task { await viewModel.logFood(food, quantity: servings, mealSlotId: slot.id, date: date) }
                    }
                }
                optionsRow

                if entries.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 18) {
                        ForEach(categoryParts, id: \.category) { part in
                            VStack(alignment: .leading, spacing: 8) {
                                partHeader(part.category, part.items)
                                ForEach(part.items) { slotEntry in
                                    foodCard(slotEntry)
                                }
                            }
                        }
                    }
                }

                if !entries.isEmpty {
                    Button {
                        isSavingMeal = true
                    } label: {
                        Label("Save this as a meal", systemImage: "bookmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.appPrimaryCompact)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(AppColor.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .appScreen()
        .navigationTitle(slot.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $addingFood) {
            FoodPickerView(
                mealSlotName: slot.name,
                onLog: { food, quantity in
                    Task { await viewModel.logFood(food, quantity: quantity, mealSlotId: slot.id, date: date) }
                },
                carbsRemainingG: preworkoutCarbTargetG.flatMap { slot.isPreworkout ? max($0 - (group?.totalCarbsG ?? 0), 0) : nil }
            )
        }
        .sheet(isPresented: $addingSavedMeal) {
            SavedMealPickerView(
                mealSlotName: slot.name,
                onApply: { items in
                    Task { await viewModel.applySavedMeal(items, mealSlotId: slot.id, date: date) }
                },
                stock: .init(slot: slot, date: date) { summary, quantity in
                    Task { await viewModel.logRecipe(summary.recipe, quantity: quantity, mealSlotId: slot.id, date: date) }
                }
            )
        }
        .sheet(isPresented: $weighing) {
            LiveWeighView(mealSlotName: slot.name) { food, servings in
                Task { await viewModel.logFood(food, quantity: servings, mealSlotId: slot.id, date: date) }
            }
        }
        .sheet(isPresented: $copyingMeal) {
            CopyMealView(slot: slot, slots: viewModel.mealSlots) { source in
                Task { await viewModel.copyEntries(source, mealSlotId: slot.id, date: date) }
            }
        }
        .sheet(isPresented: $isSavingMeal) {
            SaveMealSheet(entries: viewModel.entries(forSlot: slot.id)) {}
        }
        .sheet(item: $editingEntry) { slotEntry in
            EditMealEntryQuantityView(
                entry: slotEntry,
                onConfirm: { newQuantity in
                    Task { await viewModel.updateQuantity(slotEntry.entry, quantity: newQuantity) }
                },
                onRemove: {
                    Task { await viewModel.deleteEntry(slotEntry.entry) }
                },
                onSetEatenAt: { time in
                    Task { await viewModel.updateEatenAt(slotEntry.entry, eatenAt: time) }
                },
                onAddSalt: { grams in
                    Task {
                        // Salt is a food of its own (per 100 g), logged to this meal.
                        guard let salt = await FoodRepository().saltFood() else { return }
                        await viewModel.logFood(salt, quantity: grams / max(salt.servingSize, 1), mealSlotId: slot.id, date: date)
                    }
                }
            )
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
                    macroLine("Protein", protein, color: AppColor.protein)
                    macroLine("Carbs", carbs, color: AppColor.carbs)
                    macroLine("Fat", fat, color: AppColor.fat)
                }
                Spacer(minLength: 0)
            }
            let sodium = group?.totalSodiumMg ?? 0
            let caffeine = group?.totalCaffeineMg ?? 0
            if sodium > 0 || caffeine > 0 {
                HStack(spacing: 18) {
                    if sodium > 0 {
                        Label("\(Int(sodium.rounded())) mg sodium", systemImage: "drop.triangle")
                    }
                    if caffeine > 0 {
                        Label("\(Int(caffeine.rounded())) mg caffeine", systemImage: "cup.and.saucer")
                    }
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .appCard(cornerRadius: 16)
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
            optionButton("Saved", icon: "list.bullet.rectangle") { addingSavedMeal = true }
            optionButton("Copy", icon: "doc.on.doc") { copyingMeal = true }
            optionButton("Scale", icon: "scalemass") { weighing = true }
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
        }
        .buttonStyle(.appTile)
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
        .appCard(cornerRadius: 16)
    }

    /// One food, kept to the essentials: its name, how much you had (with the
    /// brand after it), and its calories. The meal's protein/carbs/fat are in
    /// the header above; per-item macros are in the edit sheet (tap the row).
    /// Long-press for Edit / Remove.
    private func foodCard(_ slotEntry: MealSlotEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(slotEntry.title)
                        .font(.body.weight(.medium))
                    if slotEntry.isVerified {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(AppColor.success)
                    }
                }
                Text(subtitle(for: slotEntry))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(Int(slotEntry.calories.rounded()))")
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                Text("kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: 14)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture { editingEntry = slotEntry }
        .swipeToDelete(cornerRadius: 14) {
            Task { await viewModel.deleteEntry(slotEntry.entry) }
        }
        .contextMenu {
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
        }
    }

    /// "80g" or "80g · Brand".
    private func subtitle(for slotEntry: MealSlotEntry) -> String {
        var parts = [slotEntry.amountLabel]
        if let brand = slotEntry.brand, !brand.isEmpty { parts.append(brand) }
        if let eatenAt = slotEntry.entry.eatenAt {
            parts.append(eatenAt.formatted(date: .omitted, time: .shortened))
        }
        return parts.joined(separator: " \u{00b7} ")
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
        return [(AppColor.carbs, carbs / total), (AppColor.fat, fat / total), (AppColor.protein, protein / total)]
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
    let onRemove: () -> Void
    let onSetEatenAt: (Date?) -> Void
    let onAddSalt: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var hasEatenTime: Bool
    @State private var eatenTime: Date
    @State private var saltText = ""
    @State private var quantityText: String
    @State private var inputMode: QuantityInputMode = .servings
    private let info: EditableFoodInfo?

    init(
        entry: MealSlotEntry,
        onConfirm: @escaping (Double) -> Void,
        onRemove: @escaping () -> Void,
        onSetEatenAt: @escaping (Date?) -> Void,
        onAddSalt: @escaping (Double) -> Void
    ) {
        self.entry = entry
        self.onConfirm = onConfirm
        self.onRemove = onRemove
        self.onSetEatenAt = onSetEatenAt
        _hasEatenTime = State(initialValue: entry.entry.eatenAt != nil)
        _eatenTime = State(initialValue: entry.entry.displayTime)
        self.onAddSalt = onAddSalt
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
                    .listRowBackground(AppRowBackground())
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
                        .listRowBackground(AppRowBackground())
                        Section("Adds") {
                            LabeledContent("Calories", value: "\(Int(info.caloriesPerUnit * quantity)) kcal")
                            LabeledContent("Protein", value: "\(Int(info.proteinPerUnit * quantity))g")
                            LabeledContent("Carbs", value: "\(Int(info.carbsPerUnit * quantity))g")
                            LabeledContent("Fat", value: "\(Int(info.fatPerUnit * quantity))g")
                            if let fiberPerUnit = info.fiberPerUnit {
                                LabeledContent("Fiber", value: "\(Int(fiberPerUnit * quantity))g")
                            }
                        }
                        .listRowBackground(AppRowBackground())
                    }
                }
                Section {
                    Toggle("Time eaten recorded", isOn: $hasEatenTime)
                    if hasEatenTime {
                        DatePicker("Eaten at", selection: $eatenTime, displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("When")
                } footer: {
                    Text("The time you actually ate it, for lining meals up against other readings. Foods logged as you eat them get the time automatically.")
                }
                .listRowBackground(AppRowBackground())
                Section {
                    HStack {
                        Text("Salt added")
                        Spacer()
                        TextField("0", text: $saltText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                        Text("g").foregroundStyle(.secondary)
                    }
                    if let grams = Double(saltText), grams > 0 {
                        Button("Add \(AmountLabel.trimmed(grams))g salt to this meal (\(Int((grams * 393).rounded())) mg sodium)") {
                            onAddSalt(grams)
                            saltText = ""
                        }
                    }
                } header: {
                    Text("Salt")
                } footer: {
                    Text("Logged as its own item in this meal, counted in sodium. About 393 mg of sodium per gram of salt.")
                }
                .listRowBackground(AppRowBackground())
                Section {
                    Button("Remove from Meal", role: .destructive) {
                        onRemove()
                        dismiss()
                    }
                }
                .listRowBackground(AppRowBackground())
            }
            .appScreen()
            .navigationTitle(info?.name ?? entry.name)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                    .appToolbarTint()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        if let quantity {
                            onConfirm(quantity)
                            saveEatenTime()
                            dismiss()
                        }
                    }
                    .disabled(!(quantity.map { $0 > 0 } ?? false))
                    .appToolbarTint()
                }
            }
        }
    }

    /// The picker's hour and minute, put on the entry's own day.
    private func saveEatenTime() {
        let original = entry.entry.eatenAt
        if !hasEatenTime {
            if original != nil { onSetEatenAt(nil) }
            return
        }
        let calendar = Calendar.current
        let day = DateFormatting.date(fromISODate: entry.entry.date) ?? entry.entry.displayTime
        let time = calendar.dateComponents([.hour, .minute], from: eatenTime)
        guard let combined = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day) else { return }
        if original == nil || abs(combined.timeIntervalSince(original ?? combined)) >= 60 {
            onSetEatenAt(combined)
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
