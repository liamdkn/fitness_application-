import SwiftUI

/// Builds a new recipe: a name plus a running list of foods and
/// quantities. Ingredient search reuses `FoodPickerView` as-is (its
/// `(Food, Double) -> Void` callback is exactly "food + quantity" already)
/// rather than building a second search UI - here it just appends to the
/// local ingredient list instead of logging to a meal slot.
struct RecipeBuilderView: View {
    let onCreated: (Recipe) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var ingredients: [(food: Food, quantity: Double)] = []
    @State private var showingFoodPicker = false
    @State private var errorMessage: String?
    @State private var isSaving = false
    private let repository = RecipeRepository()

    private var totals: DayMacroTotals {
        var totals = DayMacroTotals()
        for item in ingredients {
            totals.calories += item.food.calories(at: item.quantity)
            totals.proteinG += item.food.proteinG(at: item.quantity)
            totals.carbsG += item.food.carbsG(at: item.quantity)
            totals.fatG += item.food.fatG(at: item.quantity)
            totals.fiberG += item.food.fiberG(at: item.quantity) ?? 0
        }
        return totals
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !ingredients.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Recipe") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                }
                Section("Ingredients") {
                    ForEach(Array(ingredients.enumerated()), id: \.offset) { _, item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.food.displayName)
                                Text("\(quantityLabel(item.quantity)) \u{00d7} \(item.food.servingLabel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(Int(item.food.calories(at: item.quantity))) kcal")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { ingredients.remove(atOffsets: $0) }

                    Button {
                        showingFoodPicker = true
                    } label: {
                        Label("Add Ingredient", systemImage: "plus")
                    }
                }
                if !ingredients.isEmpty {
                    Section("Recipe Totals") {
                        LabeledContent("Calories", value: "\(Int(totals.calories)) kcal")
                        LabeledContent("Protein", value: "\(Int(totals.proteinG))g")
                        LabeledContent("Carbs", value: "\(Int(totals.carbsG))g")
                        LabeledContent("Fat", value: "\(Int(totals.fatG))g")
                        LabeledContent("Fiber", value: "\(Int(totals.fiberG))g")
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("New Recipe")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .disabled(!isValid || isSaving)
                }
            }
            .sheet(isPresented: $showingFoodPicker) {
                FoodPickerView(mealSlotName: "this recipe") { food, quantity in
                    ingredients.append((food, quantity))
                }
            }
        }
    }

    private func quantityLabel(_ quantity: Double) -> String {
        quantity == quantity.rounded() ? "\(Int(quantity))" : String(format: "%.1f", quantity)
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let recipe = try await repository.create(name: name.trimmingCharacters(in: .whitespaces), ingredients: ingredients)
            onCreated(recipe)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
