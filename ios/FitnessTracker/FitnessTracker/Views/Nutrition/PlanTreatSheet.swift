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

    private var isValid: Bool {
        !label.trimmingCharacters(in: .whitespaces).isEmpty && (Double(extraCalories).map { $0 > 0 } ?? false)
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
                    TextField("What's the treat? (e.g. Birthday cake)", text: $label)
                }

                Section("Extra, on top of a normal day's share") {
                    numberField("Calories", text: $extraCalories, unit: "kcal")
                    numberField("Protein", text: $extraProtein, unit: "g")
                    numberField("Carbs", text: $extraCarbs, unit: "g")
                    numberField("Fat", text: $extraFat, unit: "g")
                }

                Text("This comes off the week's totals up top, and the other days adjust to compensate - the week's budget stays the same, only how it's spread across the days changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
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
        guard let calories = Double(extraCalories) else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.createTreat(
                date: treatDate,
                mealSlotId: mealSlotId,
                label: label.trimmingCharacters(in: .whitespaces),
                extraCalories: calories,
                extraProteinG: Double(extraProtein) ?? 0,
                extraCarbsG: Double(extraCarbs) ?? 0,
                extraFatG: Double(extraFat) ?? 0
            )
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
