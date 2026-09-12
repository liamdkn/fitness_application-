import SwiftUI

/// Browse-and-pick over the user's own recipes (there's no shared recipe
/// catalog - recipes are always personal), same quantity-step pattern as
/// `FoodPickerView`.
struct RecipePickerView: View {
    let mealSlotName: String
    let onLog: (Recipe, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var recipes: [Recipe] = []
    @State private var errorMessage: String?
    @State private var pendingRecipe: Recipe?
    @State private var showingBuilder = false
    private let repository = RecipeRepository()

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                if recipes.isEmpty {
                    Text("No recipes yet - create one to log it to \(mealSlotName) in one action next time.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(recipes) { recipe in
                        Button {
                            pendingRecipe = recipe
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(recipe.name)
                                    .foregroundStyle(.primary)
                                Text("\(Int(recipe.calories)) kcal per serving")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("My Recipes")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New Recipe") { showingBuilder = true }
                }
            }
            .task { await load() }
            .sheet(item: $pendingRecipe) { recipe in
                LogRecipeQuantityView(recipe: recipe) { quantity in
                    onLog(recipe, quantity)
                    dismiss()
                }
            }
            .sheet(isPresented: $showingBuilder) {
                RecipeBuilderView { recipe in
                    recipes.append(recipe)
                    recipes.sort { $0.name < $1.name }
                }
            }
        }
    }

    private func load() async {
        do {
            recipes = try await repository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct LogRecipeQuantityView: View {
    let recipe: Recipe
    let onConfirm: (Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var quantityText = "1"

    private var quantity: Double? { Double(quantityText) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Servings")
                        Spacer()
                        TextField("1", text: $quantityText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }
                }
                if let quantity, quantity > 0 {
                    Section("Adds") {
                        LabeledContent("Calories", value: "\(Int(recipe.calories(at: quantity))) kcal")
                        LabeledContent("Protein", value: "\(Int(recipe.proteinG(at: quantity)))g")
                        LabeledContent("Carbs", value: "\(Int(recipe.carbsG(at: quantity)))g")
                        LabeledContent("Fat", value: "\(Int(recipe.fatG(at: quantity)))g")
                        LabeledContent("Fiber", value: "\(Int(recipe.fiberG(at: quantity)))g")
                    }
                }
            }
            .navigationTitle(recipe.name)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        if let quantity { onConfirm(quantity) }
                    }
                    .disabled(!(quantity.map { $0 > 0 } ?? false))
                }
            }
        }
    }
}
