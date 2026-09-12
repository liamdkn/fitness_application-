import SwiftUI

/// Browse the user's saved meals (e.g. "My Usual Breakfast") and apply one
/// to the current slot/date in a single action - each item already has
/// its own quantity from when it was saved, so there's no quantity step
/// here the way there is for a single food or recipe.
struct SavedMealPickerView: View {
    let mealSlotName: String
    let onApply: ([SavedMealItem]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var savedMeals: [SavedMeal] = []
    @State private var errorMessage: String?
    private let repository = SavedMealsRepository()

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                if savedMeals.isEmpty {
                    Text("No saved meals yet. Log a meal to \(mealSlotName), then use \"Save This Meal\" to keep it for next time.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(savedMeals) { savedMeal in
                        Button(savedMeal.name) {
                            Task { await apply(savedMeal) }
                        }
                    }
                    .onDelete { offsets in Task { await delete(at: offsets) } }
                }
            }
            .navigationTitle("Saved Meals")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        do {
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

    private func delete(at offsets: IndexSet) async {
        let toDelete = offsets.map { savedMeals[$0] }
        savedMeals.remove(atOffsets: offsets)
        for savedMeal in toDelete {
            try? await repository.delete(id: savedMeal.id)
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
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Save This Meal")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.save(name: name.trimmingCharacters(in: .whitespaces), entries: entries)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
