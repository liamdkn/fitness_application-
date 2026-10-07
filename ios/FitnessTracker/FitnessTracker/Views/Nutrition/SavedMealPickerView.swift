import SwiftUI

/// Browse the user's saved meals (e.g. "My Usual Breakfast") and apply one
/// to the current slot/date in a single action - each item already has
/// its own quantity from when it was saved, so there's no quantity step
/// here the way there is for a single food or recipe. Meals are listed
/// under their category ("Overnight oats"), uncategorised ones last.
struct SavedMealPickerView: View {
    /// Where "recipes in stock" can be logged to. When given, the batches you've
    /// made are listed at the top, above the saved meals.
    struct StockContext {
        let slot: MealSlot
        let date: Date
        let onLog: (MealPrepSummary, Double) -> Void
    }

    let mealSlotName: String
    let onApply: ([SavedMealItem]) -> Void
    var stock: StockContext?

    @Environment(\.dismiss) private var dismiss
    @State private var savedMeals: [SavedMeal] = []
    @State private var errorMessage: String?
    @State private var recategorizing: SavedMeal?
    @State private var stockItems: [MealPrepSummary] = []
    @State private var pendingPrep: MealPrepSummary?
    private let repository = SavedMealsRepository()

    /// Category sections alphabetical, "Other" (no category) at the bottom;
    /// meals within a section by name (the repository already orders by name).
    private var sections: [(title: String, meals: [SavedMeal])] {
        let grouped = Dictionary(grouping: savedMeals) { $0.category ?? "" }
        let named = grouped.keys.filter { !$0.isEmpty }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        var result = named.map { (title: $0, meals: grouped[$0] ?? []) }
        if let uncategorised = grouped[""], !uncategorised.isEmpty {
            // With no categories at all, a lone "Other" header is just noise.
            result.append((title: named.isEmpty ? "" : "Other", meals: uncategorised))
        }
        return result
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(AppColor.error)
                }
                if stock != nil {
                    Section {
                        if stockItems.isEmpty {
                            Text("Nothing in stock - make a batch from Recipes in the Meals menu.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(stockItems) { summary in
                            Button {
                                pendingPrep = summary
                            } label: {
                                MealPrepRow(summary: summary)
                                    .foregroundStyle(.primary)
                            }
                        }
                    } header: {
                        Text("Recipes in stock")
                    } footer: {
                        if !savedMeals.isEmpty { Text("Or choose a saved meal below.") }
                    }
                    .listRowBackground(AppRowBackground())
                }
                if savedMeals.isEmpty {
                    Text("No saved meals yet. Log a meal to \(mealSlotName), then use \"Save This Meal\" to keep it for next time.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sections, id: \.title) { section in
                        Section(section.title) {
                            ForEach(section.meals) { savedMeal in
                                NavigationLink {
                                    SavedMealMenuPage(savedMeal: savedMeal, mealSlotName: mealSlotName) { items in
                                        onApply(items)
                                        dismiss()
                                    }
                                } label: {
                                    Text(savedMeal.name)
                                }
                                .contextMenu {
                                    Button {
                                        Task { await apply(savedMeal) }
                                    } label: {
                                        Label("Add As Saved", systemImage: "plus.circle")
                                    }
                                    Button {
                                        recategorizing = savedMeal
                                    } label: {
                                        Label("Change Category", systemImage: "folder")
                                    }
                                }
                            }
                            .onDelete { offsets in
                                let toDelete = offsets.map { section.meals[$0] }
                                Task { await delete(toDelete) }
                            }
                        }
                        .listRowBackground(AppRowBackground())
                    }
                }
            }
            .appScreen()
            .navigationTitle(stock == nil ? "Saved Meals" : "Saved & In Stock")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                    .appToolbarTint()
                }
            }
            .task { await load() }
            .sheet(item: $pendingPrep) { summary in
                if let stock {
                    LogPrepPortionView(summary: summary, fixedSlot: stock.slot, fixedDate: stock.date) { quantity, _, _ in
                        stock.onLog(summary, quantity)
                        dismiss()
                    }
                }
            }
            .sheet(item: $recategorizing) { savedMeal in
                ChangeCategorySheet(savedMeal: savedMeal, existingCategories: existingCategories) {
                    Task { await load() }
                }
            }
        }
    }

    private var existingCategories: [String] {
        Array(Set(savedMeals.compactMap(\.category))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private func load() async {
        do {
            if stock != nil {
                stockItems = try await MealPrepRepository().fetchSummaries()
                    .filter { !$0.isFinished }
                    .sorted { $0.prep.eatBy < $1.prep.eatBy }
            }
            savedMeals = try await repository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ savedMeal: SavedMeal) async {
        do {
            let items = try await repository.fetchItems(savedMealId: savedMeal.id)
            onApply(items)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ toDelete: [SavedMeal]) async {
        let ids = Set(toDelete.map(\.id))
        savedMeals.removeAll { ids.contains($0.id) }
        for savedMeal in toDelete {
            try? await repository.delete(id: savedMeal.id)
        }
    }
}

/// Pick an existing category, start a new one, or none - shared by the
/// save sheet and the change-category sheet. `category` is "" for none.
struct SavedMealCategoryField: View {
    private enum Choice: Hashable {
        case none, existing(String), new
    }

    @Binding var category: String
    let existingCategories: [String]

    @State private var choice: Choice = .none
    @State private var newName = ""
    @State private var didSetInitialChoice = false

    var body: some View {
        Section {
            Picker("Category", selection: $choice) {
                Text("None").tag(Choice.none)
                ForEach(existingCategories, id: \.self) { name in
                    Text(name).tag(Choice.existing(name))
                }
                Text("New category...").tag(Choice.new)
            }
            if choice == .new {
                TextField("e.g. Overnight oats", text: $newName)
                    .textInputAutocapitalization(.words)
            }
        } footer: {
            Text("Groups saved meals together in the Saved Meals list.")
        }
        .listRowBackground(AppRowBackground())
        .onAppear(perform: setInitialChoice)
        .onChange(of: choice) { sync() }
        .onChange(of: newName) { sync() }
    }

    /// Opens on whatever `category` already is - a known one, or a custom
    /// one carried in as the new-category text.
    private func setInitialChoice() {
        guard !didSetInitialChoice else { return }
        didSetInitialChoice = true
        if category.isEmpty {
            choice = .none
        } else if existingCategories.contains(category) {
            choice = .existing(category)
        } else {
            newName = category
            choice = .new
        }
    }

    private func sync() {
        switch choice {
        case .none: category = ""
        case let .existing(name): category = name
        case .new: category = newName.trimmingCharacters(in: .whitespaces)
        }
    }
}

/// Names and snapshots a meal slot's current entries into a new saved
/// meal - shown from `MealLogSection`'s per-slot menu, only when that
/// slot has at least one entry to snapshot.
struct SaveMealSheet: View {
    let entries: [MealEntry]
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category = ""
    @State private var existingCategories: [String] = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    private let repository = SavedMealsRepository()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. \"My Usual Breakfast\")", text: $name)
                        .textInputAutocapitalization(.words)
                }
                .listRowBackground(AppRowBackground())
                SavedMealCategoryField(category: $category, existingCategories: existingCategories)
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(AppColor.error)
                }
            }
            .appScreen()
            .navigationTitle("Save This Meal")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                    .appToolbarTint()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    .appToolbarTint()
                }
            }
            .task {
                existingCategories = (try? await repository.fetchCategories()) ?? []
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.save(name: name.trimmingCharacters(in: .whitespaces), category: category, entries: entries)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Moves an already-saved meal to a different category (or out of one) -
/// reached from a saved meal's long-press menu.
private struct ChangeCategorySheet: View {
    let savedMeal: SavedMeal
    let existingCategories: [String]
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var category: String
    @State private var errorMessage: String?
    private let repository = SavedMealsRepository()

    init(savedMeal: SavedMeal, existingCategories: [String], onSaved: @escaping () -> Void) {
        self.savedMeal = savedMeal
        self.existingCategories = existingCategories
        self.onSaved = onSaved
        _category = State(initialValue: savedMeal.category ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                SavedMealCategoryField(category: $category, existingCategories: existingCategories)
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(AppColor.error)
                }
            }
            .appScreen()
            .navigationTitle(savedMeal.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                    .appToolbarTint()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                    .appToolbarTint()
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() async {
        do {
            try await repository.updateCategory(id: savedMeal.id, category: category)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
