import SwiftUI

/// Banks a treat - picks a day in the given week, which meal it'll land
/// in, and how much *extra* (over a normal day's share) it's going to
/// need. `CalorieBankCalculator` does the actual redistribution; this
/// sheet only writes the plan itself. Reused from both `TreatsPlannerView`
/// (the weekly totals screen a treat is actually managed from) and
/// nowhere else now - `MealLogHomeView` links to that screen rather than
/// opening this directly, so "add a treat" always starts from seeing the
/// week's totals it's about to come off of.
struct PlanTreatSheet: View {
    let weekDates: [Date]
    let mealSlots: [MealSlot]
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var treatDate: Date
    @State private var mealSlotId: UUID?
    @State private var label = ""
    @State private var extraCalories = ""
    @State private var extraProtein = ""
    @State private var extraCarbs = ""
    @State private var extraFat = ""
    /// Foods making up the treat, added with the same search as any meal.
    /// When there are any, the treat's calories/macros are their sum and the
    /// manual fields below step aside.
    @State private var items: [(food: Food, quantity: Double)] = []
    @State private var showingFoodPicker = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    private let repository = PlannedTreatRepository()

    init(weekDates: [Date], mealSlots: [MealSlot], onSaved: @escaping () async -> Void) {
        self.weekDates = weekDates
        self.mealSlots = mealSlots
        self.onSaved = onSaved
        let today = Calendar.current.startOfDay(for: Date())
        _treatDate = State(initialValue: weekDates.first { $0 >= today } ?? weekDates.first ?? Date())
        _mealSlotId = State(initialValue: mealSlots.first?.id)
    }

    /// Calories vs the macros typed in - `nil` until calories are entered.
    /// Enforced here (not just warned): the treat is the app's own number,
    /// and it comes off the week's macro budgets, so a 1000 kcal treat with
    /// 16 g of protein and nothing else would quietly under-count carbs and fat.
    private var energyCheck: MacroEnergy.Check? {
        guard let calories = Double(extraCalories), calories > 0 else { return nil }
        return MacroEnergy.check(
            calories: calories,
            protein: Double(extraProtein) ?? 0,
            carbs: Double(extraCarbs) ?? 0,
            fat: Double(extraFat) ?? 0
        )
    }

    private var itemTotals: DayMacroTotals {
        RecipeRepository.totals(for: items)
    }

    /// Named after what's in it if no name was typed - "Pizza + Ice Cream".
    private var effectiveLabel: String {
        let typed = label.trimmingCharacters(in: .whitespaces)
        if !typed.isEmpty { return typed }
        return items.map(\.food.name).joined(separator: " + ")
    }

    private var isValid: Bool {
        guard !effectiveLabel.isEmpty else { return false }
        // Built from foods, the totals are a sum, so they agree by construction.
        if !items.isEmpty { return itemTotals.calories > 0 }
        return energyCheck?.isConsistent ?? false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Day", selection: $treatDate) {
                        ForEach(weekDates, id: \.self) { date in
                            Text(dayLabel(date)).tag(date)
                        }
                    }
                    if !mealSlots.isEmpty {
                        Picker("Meal", selection: $mealSlotId) {
                            ForEach(mealSlots) { slot in
                                Text(slot.name).tag(slot.id as UUID?)
                            }
                        }
                    }
                    TextField(items.isEmpty ? "What's the treat? (e.g. Birthday cake)" : "Name (optional)", text: $label)
                }

                Section {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.food.displayName)
                                Text(item.food.amountLabel(at: item.quantity))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(Int(item.food.calories(at: item.quantity).rounded())) kcal")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { items.remove(atOffsets: $0) }
                    Button {
                        showingFoodPicker = true
                    } label: {
                        Label("Add Food", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("What's in it")
                } footer: {
                    Text(items.isEmpty
                         ? "Search for the foods like you would for a meal and add as many as you like. Or skip this and type the totals below."
                         : "The treat's calories and macros are the total of these.")
                }

                if items.isEmpty {
                    Section("Or enter the totals - extra, on top of a normal day's share") {
                        numberField("Calories", text: $extraCalories, unit: "kcal")
                        numberField("Protein", text: $extraProtein, unit: "g")
                        numberField("Carbs", text: $extraCarbs, unit: "g")
                        numberField("Fat", text: $extraFat, unit: "g")
                        if let energyCheck {
                            energyRow(energyCheck)
                        }
                    }
                } else {
                    Section("Total - extra, on top of a normal day's share") {
                        LabeledContent("Calories", value: "\(Int(itemTotals.calories.rounded())) kcal")
                        LabeledContent("Protein", value: "\(Int(itemTotals.proteinG.rounded()))g")
                        LabeledContent("Carbs", value: "\(Int(itemTotals.carbsG.rounded()))g")
                        LabeledContent("Fat", value: "\(Int(itemTotals.fatG.rounded()))g")
                    }
                }

                Text("This comes off the week's totals up top, and the other days adjust to compensate - the week's budget stays the same, only how it's spread across the days changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .sheet(isPresented: $showingFoodPicker) {
                FoodPickerView(mealSlotName: "Treat") { food, quantity in
                    items.append((food, quantity))
                }
            }
            .navigationTitle("Plan a Treat")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .disabled(!isValid || isSaving)
                }
            }
        }
    }

    /// Whether the macros cover the calories - and a one-tap way to make
    /// them: spread the leftover over carbs and fat when macros fall short,
    /// or raise the calories to match when they overshoot.
    @ViewBuilder
    private func energyRow(_ check: MacroEnergy.Check) -> some View {
        if check.isConsistent {
            Label("Macros add up to the calories", systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.green)
        } else if check.unassignedKcal > 0 {
            VStack(alignment: .leading, spacing: 8) {
                Label("\(Int(check.unassignedKcal.rounded())) of \(Int(check.calories.rounded())) kcal isn't covered by the macros", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                Button("Fill the rest as carbs and fat") {
                    let rest = MacroEnergy.fillRemainder(kcal: check.unassignedKcal)
                    extraCarbs = format((Double(extraCarbs) ?? 0) + rest.carbsG)
                    extraFat = format((Double(extraFat) ?? 0) + rest.fatG)
                }
                .font(.footnote.bold())
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("The macros add up to \(Int(check.macroKcal.rounded())) kcal, more than the \(Int(check.calories.rounded())) entered", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                Button("Set calories to \(Int(check.macroKcal.rounded()))") {
                    extraCalories = format(check.macroKcal.rounded())
                }
                .font(.footnote.bold())
            }
        }
    }

    private func format(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }

    @ViewBuilder
    private func numberField(_ title: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMM"
        return formatter.string(from: date)
    }

    private func save() async {
        let totals: (calories: Double, protein: Double, carbs: Double, fat: Double)
        if items.isEmpty {
            guard let calories = Double(extraCalories) else { return }
            totals = (calories, Double(extraProtein) ?? 0, Double(extraCarbs) ?? 0, Double(extraFat) ?? 0)
        } else {
            totals = (itemTotals.calories, itemTotals.proteinG, itemTotals.carbsG, itemTotals.fatG)
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.createTreat(
                date: treatDate,
                mealSlotId: mealSlotId,
                label: effectiveLabel,
                extraCalories: totals.calories,
                extraProteinG: totals.protein,
                extraCarbsG: totals.carbs,
                extraFatG: totals.fat
            )
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
