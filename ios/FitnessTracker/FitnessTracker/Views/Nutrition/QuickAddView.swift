import SwiftUI

/// Log just calories and macros - "a slice of cake, about 350 kcal" - without
/// adding anything to the food database. Macro maths is shown as a warning
/// only; it never blocks adding. It's recorded as a hidden one-off
/// item (`Food.isQuickAdd`), which every total in the app can read like any
/// food but which never shows up in search, recents or the Food Database.
struct QuickAddView: View {
    /// Called with the created item once saved; the picker logs it straight away.
    let onAdded: (Food) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var caloriesValue: Double? {
        guard let value = Double(calories), value > 0 else { return nil }
        return value
    }

    /// How the macros add up against the calories (4/4/9 kcal per gram).
    /// Only once calories and at least one macro are entered - and only ever
    /// a warning: a quick add is an estimate, so it never blocks Add.
    private var energyCheck: MacroEnergy.Check? {
        guard let cal = caloriesValue, !(protein.isEmpty && carbs.isEmpty && fat.isEmpty) else { return nil }
        return MacroEnergy.check(
            calories: cal,
            protein: Double(protein) ?? 0,
            carbs: Double(carbs) ?? 0,
            fat: Double(fat) ?? 0,
            tolerance: .strict
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What was it? (optional)", text: $name)
                    field("Calories", text: $calories, unit: "kcal")
                }
                .listRowBackground(AppRowBackground())

                Section("Macros (optional)") {
                    field("Protein", text: $protein, unit: "g")
                    field("Carbs", text: $carbs, unit: "g")
                    field("Fat", text: $fat, unit: "g")
                    if let check = energyCheck {
                        energyRow(check)
                    }
                }
                .listRowBackground(AppRowBackground())

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(AppColor.error)
                }
            }
            .appScreen()
            .navigationTitle("Quick Add")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .appToolbarTint()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") { Task { await save() } }
                        .disabled(caloriesValue == nil || isSaving)
                        .appToolbarTint()
                }
            }
        }
    }

    @ViewBuilder
    private func energyRow(_ check: MacroEnergy.Check) -> some View {
        if check.isConsistent {
            Label("Macros add up: \(Int(check.macroKcal.rounded())) kcal", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(AppColor.success)
        } else if check.unassignedKcal > 0 {
            VStack(alignment: .leading, spacing: 6) {
                Label(
                    "These macros come to \(Int(check.macroKcal.rounded())) kcal - \(Int(check.unassignedKcal.rounded())) of the \(Int(check.calories.rounded())) kcal isn't covered.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(AppColor.warning)
                Button("Fill the rest with carbs and fat") {
                    let rest = MacroEnergy.fillRemainder(kcal: check.unassignedKcal)
                    carbs = format((Double(carbs) ?? 0) + rest.carbsG)
                    fat = format((Double(fat) ?? 0) + rest.fatG)
                }
                .font(.caption.weight(.semibold))
            }
        } else {
            Label(
                "These macros come to \(Int(check.macroKcal.rounded())) kcal - \(Int((-check.unassignedKcal).rounded())) more than the \(Int(check.calories.rounded())) kcal entered.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(AppColor.warning)
        }
    }

    private func format(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }

    private func field(_ label: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(unit).foregroundStyle(.secondary).font(.caption)
        }
    }

    private func save() async {
        guard let calories = caloriesValue else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            let food = try await FoodRepository().createCustom(
                name: trimmed.isEmpty ? "Quick add" : trimmed,
                brand: nil,
                servingSize: 1,
                servingUnit: "item",
                calories: calories,
                proteinG: Double(protein) ?? 0,
                carbsG: Double(carbs) ?? 0,
                fatG: Double(fat) ?? 0,
                fiberG: nil,
                // Verified, so it goes straight in with no "check this food" step.
                isVerified: true,
                source: Food.quickAddSource
            )
            onAdded(food)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
