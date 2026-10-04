import SwiftUI

/// One saved meal as a menu page: its protein, carb and fat sources, each one
/// swappable for another food that carries the same amount of that macro, and
/// a fit button that sizes the whole meal to macro targets.
struct SavedMealMenuPage: View {
    let savedMeal: SavedMeal
    let mealSlotName: String
    let onApply: ([SavedMealItem]) -> Void

    /// One food in the meal as it stands now.
    private struct Row: Identifiable {
        let id = UUID()
        var food: Food
        var servings: Double
        var role: FoodCategory { food.primaryCategory ?? .other }
        var macros: MealFitter.Macros {
            MealFitter.Macros(calories: food.calories(at: servings), protein: food.proteinG(at: servings),
                              carbs: food.carbsG(at: servings), fat: food.fatG(at: servings))
        }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var rows: [Row] = []
    @State private var original: [Row] = []
    /// Recipes in the meal: not adjustable, added exactly as saved.
    @State private var recipeItems: [SavedMealItem] = []
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var swapping: Row?
    @State private var proteinTarget = ""
    @State private var carbsTarget = ""
    @State private var fatTarget = ""
    @State private var targetsSeeded = false
    private let repository = SavedMealsRepository()

    private var totals: MealFitter.Macros { rows.reduce(MealFitter.Macros()) { $0 + $1.macros } }

    var body: some View {
        List {
            Section {
                macroHeader
            }
            .listRowBackground(AppRowBackground())

            ForEach(FoodCategory.allCases.sorted { $0.sortOrder < $1.sortOrder }) { role in
                let items = rows.filter { $0.role == role }
                if !items.isEmpty {
                    Section(role == .other ? "Other" : "\(role.displayName) source") {
                        ForEach(items) { row in
                            rowView(row, role: role)
                        }
                    }
                    .listRowBackground(AppRowBackground())
                }
            }

            Section {
                targetField("Protein", $proteinTarget)
                targetField("Carbs", $carbsTarget)
                targetField("Fat", $fatTarget)
                Button {
                    fit()
                } label: {
                    Label("Fit the Meal to These", systemImage: "scope")
                }
                if hasChanges {
                    Button("Back to the Saved Meal", role: .destructive) {
                        rows = original
                        seedTargets()
                    }
                }
            } header: {
                Text("Fit to macros")
            } footer: {
                Text("Resizes the protein, carb and fat sources so the meal comes to these totals. Leave a box empty to keep that macro as it is.")
            }
            .listRowBackground(AppRowBackground())

            if let errorMessage {
                Text(errorMessage).foregroundStyle(AppColor.error)
                    .listRowBackground(Color.clear)
            }
        }
        .appScreen()
        .navigationTitle(savedMeal.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button("Add to \(mealSlotName)") { apply() }
                .buttonStyle(.appPrimary)
                .disabled(rows.isEmpty && recipeItems.isEmpty)
                .padding()
        }
        .task { await load() }
        .sheet(item: $swapping) { row in
            NavigationStack {
                FoodDatabaseView(onSelect: { replacement in swap(row, with: replacement) })
            }
        }
    }

    private var hasChanges: Bool {
        rows.map { [$0.food.id.uuidString, String($0.servings)] } != original.map { [$0.food.id.uuidString, String($0.servings)] }
    }

    private var macroHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(Int(totals.calories.rounded())) kcal")
                    .font(.title3.bold())
                    .monospacedDigit()
                Text(savedMeal.category ?? "Saved meal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            macro("P", totals.protein, AppColor.protein)
            macro("C", totals.carbs, AppColor.carbs)
            macro("F", totals.fat, AppColor.fat)
        }
    }

    private func macro(_ label: String, _ grams: Double, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text("\(Int(grams.rounded()))g").font(.subheadline.bold()).monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(color)
        }
        .frame(minWidth: 40)
    }

    private func rowView(_ row: Row, role: FoodCategory) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.food.name).font(.body.weight(.medium))
                Text("\(row.food.amountLabel(at: row.servings)) \u{00b7} \(Int(row.macros.calories.rounded())) kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if role != .other {
                Button("Swap") { swapping = row }
                    .buttonStyle(.appSecondaryCompact)
            }
        }
    }

    private func targetField(_ label: String, _ text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("-", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 70)
            Text("g").foregroundStyle(.secondary)
        }
    }

    // MARK: Actions

    /// A swapped-in food takes over the amount of that macro the old one gave:
    /// the same grams of protein, carbs or fat.
    private func swap(_ row: Row, with replacement: Food) {
        guard let index = rows.firstIndex(where: { $0.id == row.id }) else { return }
        let role = row.role
        let grams: Double = switch role {
        case .protein: row.macros.protein
        case .carb: row.macros.carbs
        case .fat: row.macros.fat
        case .other: 0
        }
        guard let needed = MealFitter.servings(of: replacement, matching: grams, role: role) else {
            errorMessage = "\(replacement.name) doesn't have enough \(role.displayName.lowercased()) to stand in for \(row.food.name)."
            return
        }
        errorMessage = nil
        rows[index] = Row(food: replacement, servings: MealFitter.practical(servings: needed, food: replacement))
    }

    private func fit() {
        func lines(_ role: FoodCategory) -> [MealFitter.Line] {
            rows.filter { $0.role == role }.map {
                MealFitter.Line(perServing: MealFitter.Macros(calories: $0.food.calories, protein: $0.food.proteinG, carbs: $0.food.carbsG, fat: $0.food.fatG), servings: $0.servings)
            }
        }
        let scale = MealFitter.fit(
            protein: lines(.protein), carbs: lines(.carb), fat: lines(.fat), fixed: lines(.other),
            targets: MealFitter.Targets(protein: Double(proteinTarget), carbs: Double(carbsTarget), fat: Double(fatTarget))
        )
        rows = rows.map { row in
            var row = row
            let factor: Double? = switch row.role {
            case .protein: scale.protein
            case .carb: scale.carbs
            case .fat: scale.fat
            case .other: nil
            }
            if let factor { row.servings = MealFitter.practical(servings: row.servings * factor, food: row.food) }
            return row
        }
    }

    private func apply() {
        let items = rows.map {
            SavedMealItem(id: UUID(), savedMealId: savedMeal.id, foodId: $0.food.id, recipeId: nil, quantity: $0.servings)
        } + recipeItems
        onApply(items)
        dismiss()
    }

    private func seedTargets() {
        proteinTarget = String(Int(totals.protein.rounded()))
        carbsTarget = String(Int(totals.carbs.rounded()))
        fatTarget = String(Int(totals.fat.rounded()))
    }

    private func load() async {
        guard loading else { return }
        do {
            let items = try await repository.fetchItems(savedMealId: savedMeal.id)
            let foods = Dictionary(uniqueKeysWithValues: try await FoodRepository().fetchByIds(items.compactMap(\.foodId)).map { ($0.id, $0) })
            rows = items.compactMap { item in
                item.foodId.flatMap { foods[$0] }.map { Row(food: $0, servings: item.quantity) }
            }
            // Recipes can't be swapped piece by piece, so they're added as saved.
            recipeItems = items.filter { $0.recipeId != nil }
            if !recipeItems.isEmpty {
                errorMessage = "This meal includes a recipe, which can't be adjusted here - it's added as saved."
            }
            original = rows
            seedTargets()
            loading = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
