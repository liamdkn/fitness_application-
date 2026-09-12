import SwiftUI

/// Search-and-pick pattern copied directly from `ExercisePickerView` -
/// search a shared catalog (here: `foods`, seeded + growing via custom
/// additions and later Open Food Facts lookups), fall back to adding your
/// own. The one addition over that pattern is a quantity step after
/// picking, since a food (unlike an exercise) needs "how many servings"
/// before it means anything.
struct FoodPickerView: View {
    let mealSlotName: String
    let onLog: (Food, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var results: [Food] = []
    @State private var errorMessage: String?
    @State private var pendingFood: Food?
    @State private var showingAddCustom = false
    @State private var showingScanner = false
    private let repository = FoodRepository()

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                Button {
                    showingScanner = true
                } label: {
                    Label("Scan Barcode", systemImage: "barcode.viewfinder")
                }
                if searchText.isEmpty {
                    Text("Search for a food to log to \(mealSlotName).")
                        .foregroundStyle(.secondary)
                } else if results.isEmpty {
                    Text("No matches - try a different search, or add a new food.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(results) { food in
                        Button {
                            pendingFood = food
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(food.displayName)
                                    .foregroundStyle(.primary)
                                Text("\(Int(food.calories)) kcal per \(food.servingLabel)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search foods")
            // `.task(id:)` cancels the previous search when `searchText`
            // changes again before it resolves - without that, an
            // in-flight request for an earlier, shorter keystroke (e.g.
            // "c") can resolve AFTER a later, more specific one (e.g.
            // "chicken") and clobber it with a broader, wrong-looking
            // result list.
            .task(id: searchText) {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                await search(searchText)
            }
            .navigationTitle("Add Food")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New Food") { showingAddCustom = true }
                }
            }
            .sheet(item: $pendingFood) { food in
                LogFoodQuantityView(food: food) { quantity in
                    onLog(food, quantity)
                    dismiss()
                }
            }
            .sheet(isPresented: $showingAddCustom) {
                AddCustomFoodView { food in
                    pendingFood = food
                }
            }
            .sheet(isPresented: $showingScanner) {
                BarcodeScannerView { food in
                    pendingFood = food
                }
            }
        }
    }

    private func search(_ query: String) async {
        do {
            results = try await repository.search(query: query)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct LogFoodQuantityView: View {
    let food: Food
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
                        Text("\u{00d7} \(food.servingLabel)")
                            .foregroundStyle(.secondary)
                    }
                }
                if let quantity, quantity > 0 {
                    Section("Adds") {
                        LabeledContent("Calories", value: "\(Int(food.calories(at: quantity))) kcal")
                        LabeledContent("Protein", value: "\(Int(food.proteinG(at: quantity)))g")
                        LabeledContent("Carbs", value: "\(Int(food.carbsG(at: quantity)))g")
                        LabeledContent("Fat", value: "\(Int(food.fatG(at: quantity)))g")
                        if let fiber = food.fiberG(at: quantity) {
                            LabeledContent("Fiber", value: "\(Int(fiber))g")
                        }
                    }
                }
            }
            .navigationTitle(food.name)
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

private struct AddCustomFoodView: View {
    let onCreated: (Food) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var brand = ""
    @State private var servingSize = "100"
    @State private var servingUnit = "g"
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var fiber = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    private let repository = FoodRepository()

    private var isValid: Bool {
        !name.isEmpty && Double(servingSize) != nil && !servingUnit.isEmpty
            && Double(calories) != nil && Double(protein) != nil && Double(carbs) != nil && Double(fat) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("Brand (optional)", text: $brand)
                }
                Section("Serving") {
                    HStack {
                        TextField("Size", text: $servingSize)
                            .keyboardType(.decimalPad)
                        TextField("Unit (g, ml, slice...)", text: $servingUnit)
                    }
                }
                Section("Per Serving") {
                    numberField("Calories", text: $calories, unit: "kcal")
                    numberField("Protein", text: $protein, unit: "g")
                    numberField("Carbs", text: $carbs, unit: "g")
                    numberField("Fat", text: $fat, unit: "g")
                    numberField("Fiber (optional)", text: $fiber, unit: "g")
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("New Food")
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
    private func numberField(_ label: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func save() async {
        guard let size = Double(servingSize), let cal = Double(calories),
              let p = Double(protein), let c = Double(carbs), let f = Double(fat)
        else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let food = try await repository.createCustom(
                name: name,
                brand: brand.isEmpty ? nil : brand,
                servingSize: size,
                servingUnit: servingUnit,
                calories: cal,
                proteinG: p,
                carbsG: c,
                fatG: f,
                fiberG: Double(fiber)
            )
            onCreated(food)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
