import SwiftUI

struct MealSlotsSettingsView: View {
    @State private var slots: [MealSlot] = []
    @State private var errorMessage: String?
    @State private var showingAddAlert = false
    @State private var renamingSlot: MealSlot?
    @State private var textInput = ""
    private let repository = MealSlotsRepository()

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            ForEach(slots) { slot in
                Text(slot.name)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        textInput = slot.name
                        renamingSlot = slot
                    }
            }
            .onDelete { offsets in Task { await delete(at: offsets) } }
            .onMove { source, destination in Task { await move(from: source, to: destination) } }
        }
        .navigationTitle("Meal Slots")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    textInput = ""
                    showingAddAlert = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { await load() }
        .alert("New Meal Slot", isPresented: $showingAddAlert) {
            TextField("Name", text: $textInput)
            Button("Cancel", role: .cancel) {}
            Button("Add") { Task { await add() } }
        }
        .alert(
            "Rename Meal Slot",
            isPresented: Binding(get: { renamingSlot != nil }, set: { if !$0 { renamingSlot = nil } })
        ) {
            TextField("Name", text: $textInput)
            Button("Cancel", role: .cancel) {}
            Button("Save") { Task { await rename() } }
        }
    }

    private func load() async {
        do {
            slots = try await repository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func add() async {
        let trimmed = textInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            let slot = try await repository.add(name: trimmed)
            slots.append(slot)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rename() async {
        let trimmed = textInput.trimmingCharacters(in: .whitespaces)
        guard let renamingSlot, !trimmed.isEmpty else { return }
        do {
            let updated = try await repository.rename(id: renamingSlot.id, name: trimmed)
            if let index = slots.firstIndex(where: { $0.id == updated.id }) {
                slots[index] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(at offsets: IndexSet) async {
        let toDelete = offsets.map { slots[$0] }
        slots.remove(atOffsets: offsets)
        for slot in toDelete {
            try? await repository.delete(id: slot.id)
        }
    }

    private func move(from source: IndexSet, to destination: Int) async {
        slots.move(fromOffsets: source, toOffset: destination)
        let orderedIds = slots.map(\.id)
        try? await repository.reorder(orderedIds: orderedIds)
    }
}
