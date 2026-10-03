import SwiftUI

/// Browse named, deliberately-curated day snapshots ("Perfect Cut Day",
/// "Leg Day Fuel") and apply one to any target date in one action. Shows
/// each one's cached totals so picking one that fits today doesn't need
/// opening it first.
struct SavedDaysPickerView: View {
    let onApply: ([SavedDayItem]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var savedDays: [SavedDay] = []
    @State private var errorMessage: String?
    private let repository = SavedDaysRepository()

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(AppColor.error)
                }
                if savedDays.isEmpty {
                    Text("No saved days yet. Use \"Save This Day\" once you've logged a day worth keeping.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(savedDays) { savedDay in
                        Button {
                            Task { await apply(savedDay) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(savedDay.name)
                                    .foregroundStyle(.primary)
                                Text("\(Int(savedDay.calories)) kcal \u{00b7} P\(Int(savedDay.proteinG))g \u{00b7} C\(Int(savedDay.carbsG))g \u{00b7} F\(Int(savedDay.fatG))g")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in Task { await delete(at: offsets) } }
                }
            }
            .appScreen()
            .navigationTitle("Saved Days")
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
            savedDays = try await repository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ savedDay: SavedDay) async {
        do {
            let items = try await repository.fetchItems(savedDayId: savedDay.id)
            onApply(items)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(at offsets: IndexSet) async {
        let toDelete = offsets.map { savedDays[$0] }
        savedDays.remove(atOffsets: offsets)
        for savedDay in toDelete {
            try? await repository.delete(id: savedDay.id)
        }
    }
}

/// Names and snapshots the whole day's current entries (every slot) into
/// a new saved day - shown from the day view's "Day Actions" menu, only
/// when there's at least one entry logged that day.
struct SaveDaySheet: View {
    let totals: DayMacroTotals
    let entries: [MealEntry]
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    private let repository = SavedDaysRepository()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. \"Perfect Cut Day\")", text: $name)
                        .textInputAutocapitalization(.words)
                } footer: {
                    Text("\(Int(totals.calories)) kcal \u{00b7} P\(Int(totals.proteinG))g \u{00b7} C\(Int(totals.carbsG))g \u{00b7} F\(Int(totals.fatG))g will be saved as this day's totals.")
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(AppColor.error)
                }
            }
            .appScreen()
            .navigationTitle("Save This Day")
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
            try await repository.save(name: name.trimmingCharacters(in: .whitespaces), totals: totals, entries: entries)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
