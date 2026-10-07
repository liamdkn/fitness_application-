import SwiftUI

/// How much of a batch to eat: portions (1, 0.5, 2...) or, when the
/// finished batch was weighed, the grams actually served. Either way it
/// resolves to the servings multiplier a `meal_entries` row stores, since a
/// prep's recipe serving *is* one portion.
struct LogPrepPortionView: View {
    private enum Mode: Hashable { case portions, grams }

    let summary: MealPrepSummary
    /// Set when the slot/date are already decided (logging from a slot's own
    /// screen); `nil` shows pickers for both (logging from the prep itself).
    let fixedSlot: MealSlot?
    let fixedDate: Date?
    let onLog: (Double, MealSlot, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var mode: Mode = .portions
    @State private var amountText = "1"
    @State private var slots: [MealSlot] = []
    @State private var selectedSlotId: UUID?
    @State private var date = Date()

    private var portionWeightG: Double? { summary.prep.portionWeightG }

    private var quantity: Double? {
        guard let entered = Double(amountText), entered > 0 else { return nil }
        switch mode {
        case .portions: return entered
        case .grams:
            guard let portionWeightG, portionWeightG > 0 else { return nil }
            return entered / portionWeightG
        }
    }

    private var chosenSlot: MealSlot? {
        fixedSlot ?? slots.first { $0.id == selectedSlotId }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let fixedSlot {
                        LabeledContent("Meal", value: fixedSlot.name)
                    } else {
                        Picker("Meal", selection: $selectedSlotId) {
                            ForEach(slots) { slot in
                                Text(slot.name).tag(Optional(slot.id))
                            }
                        }
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                    }
                    if portionWeightG != nil {
                        Picker("Enter as", selection: $mode) {
                            Text("Portions").tag(Mode.portions)
                            Text("Grams").tag(Mode.grams)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: mode) { oldMode, newMode in
                            convert(from: oldMode, to: newMode)
                        }
                    }
                    HStack {
                        Text(mode == .portions ? "Portions" : "Served")
                        Spacer()
                        TextField("1", text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        if mode == .grams { Text("g").foregroundStyle(.secondary) }
                    }
                } footer: {
                    Text("\(MealPrepCalculator.label(summary.remainingPortions)) of \(MealPrepCalculator.label(summary.prep.portions)) portions left.")
                }
                .listRowBackground(AppRowBackground())

                if let quantity {
                    Section {
                        MacroBreakdownRing(
                            calories: summary.recipe.calories(at: quantity),
                            carbsG: summary.recipe.carbsG(at: quantity),
                            fatG: summary.recipe.fatG(at: quantity),
                            proteinG: summary.recipe.proteinG(at: quantity)
                        )
                        .padding(.vertical, 8)
                    }
                    .listRowBackground(AppRowBackground())
                    Section("Adds") {
                        LabeledContent("Calories", value: "\(Int(summary.recipe.calories(at: quantity))) kcal")
                        LabeledContent("Protein", value: "\(Int(summary.recipe.proteinG(at: quantity)))g")
                        LabeledContent("Carbs", value: "\(Int(summary.recipe.carbsG(at: quantity)))g")
                        LabeledContent("Fat", value: "\(Int(summary.recipe.fatG(at: quantity)))g")
                    }
                    .listRowBackground(AppRowBackground())
                }
            }
            .appScreen()
            .navigationTitle(summary.prep.name)
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                    .appToolbarTint()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Log") {
                        if let quantity, let chosenSlot {
                            onLog(quantity, chosenSlot, fixedDate ?? date)
                            dismiss()
                        }
                    }
                    .disabled(quantity == nil || chosenSlot == nil)
                    .appToolbarTint()
                }
            }
            .task {
                guard fixedSlot == nil else { return }
                slots = (try? await MealSlotsRepository().fetchAll()) ?? []
                selectedSlotId = slots.first?.id
            }
        }
        .presentationDetents([.large])
    }

    /// Carries the number across when the unit flips - 1 portion of a
    /// 350g batch portion reads as 350 grams, and back.
    private func convert(from oldMode: Mode, to newMode: Mode) {
        guard oldMode != newMode, let entered = Double(amountText), let portionWeightG else { return }
        let converted = newMode == .grams ? entered * portionWeightG : entered / portionWeightG
        amountText = converted == converted.rounded() ? "\(Int(converted))" : String(format: "%.1f", converted)
    }
}
