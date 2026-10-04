import SwiftUI

/// `nil` id means "adding a new one" - the same sheet handles both add and
/// rename/re-volume, file-scoped (not nested) so both
/// `WaterContainersEditView` and `ContainerEditorSheet` can share it.
private struct EditingContainer: Identifiable {
    let id: UUID?
    var name: String
    var volumeMl: String
}

/// CRUD list of the user's water containers and their volumes - not a
/// fixed catalog, since "a pint" isn't reliably 568ml for everyone who
/// pours their own.
struct WaterContainersEditView: View {
    @State private var containers: [WaterContainer] = []
    @State private var errorMessage: String?
    @State private var editingContainer: EditingContainer?
    private let repository = WaterRepository()

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(AppColor.error)
            }
            if containers.isEmpty {
                Text("Add the containers you actually drink from - a hydroflask, a pint glass, whatever - each with its own volume.")
                    .foregroundStyle(.secondary)
            }
            ForEach(containers) { container in
                Button {
                    editingContainer = EditingContainer(id: container.id, name: container.name, volumeMl: String(container.volumeMl))
                } label: {
                    HStack {
                        Text(container.name)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text("\(container.volumeMl) ml")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete(perform: removeContainers)

            Button {
                editingContainer = EditingContainer(id: nil, name: "", volumeMl: "")
            } label: {
                Label("Add Container", systemImage: "plus")
            }
        }
        .appScreen()
        .navigationTitle("Containers")
        .task { await load() }
        .sheet(item: $editingContainer) { editing in
            ContainerEditorSheet(editing: editing) { name, volumeMl in
                await save(id: editing.id, name: name, volumeMl: volumeMl)
            }
        }
    }

    private func load() async {
        do {
            containers = try await repository.fetchContainers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save(id: UUID?, name: String, volumeMl: Int) async {
        do {
            if let id {
                let updated = try await repository.updateContainer(id: id, name: name, volumeMl: volumeMl)
                if let index = containers.firstIndex(where: { $0.id == updated.id }) {
                    containers[index] = updated
                }
            } else {
                let created = try await repository.createContainer(name: name, volumeMl: volumeMl)
                containers.append(created)
            }
            containers.sort { $0.name < $1.name }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeContainers(at offsets: IndexSet) {
        let toRemove = offsets.map { containers[$0] }
        containers.remove(atOffsets: offsets)
        Task {
            for container in toRemove {
                do {
                    try await repository.deleteContainer(id: container.id)
                } catch {
                    errorMessage = error.localizedDescription
                    containers.append(container)
                    containers.sort { $0.name < $1.name }
                }
            }
        }
    }
}

private struct ContainerEditorSheet: View {
    let editing: EditingContainer
    let onSave: (String, Int) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var volumeMlText: String
    @State private var isSaving = false

    init(editing: EditingContainer, onSave: @escaping (String, Int) async -> Void) {
        self.editing = editing
        self.onSave = onSave
        _name = State(initialValue: editing.name)
        _volumeMlText = State(initialValue: editing.volumeMl)
    }

    private var volumeMl: Int? {
        let value = Int(volumeMlText)
        return (value ?? 0) > 0 ? value : nil
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && volumeMl != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name (e.g. Blue Hydraflask)", text: $name)
                HStack {
                    TextField("Volume", text: $volumeMlText)
                        .keyboardType(.numberPad)
                    Text("ml").foregroundStyle(.secondary)
                }
            }
            .appScreen()
            .navigationTitle(editing.id == nil ? "New Container" : "Edit Container")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                    .appToolbarTint()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        guard let volumeMl else { return }
                        isSaving = true
                        Task {
                            await onSave(name.trimmingCharacters(in: .whitespaces), volumeMl)
                            isSaving = false
                            dismiss()
                        }
                    }
                    .disabled(!isValid || isSaving)
                    .appToolbarTint()
                }
            }
        }
    }
}
