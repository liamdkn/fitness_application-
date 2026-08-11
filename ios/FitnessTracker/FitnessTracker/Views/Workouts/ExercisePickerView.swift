import SwiftUI

struct ExercisePickerView: View {
    let onPick: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var exercises: [Exercise] = []
    @State private var searchText = ""
    @State private var errorMessage: String?
    @State private var showingAddCustom = false
    private let repository = ExerciseRepository()

    private var filtered: [Exercise] {
        guard !searchText.isEmpty else { return exercises }
        return exercises.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                ForEach(filtered) { exercise in
                    Button {
                        onPick(exercise)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading) {
                            Text(exercise.name).foregroundStyle(.primary)
                            if let group = exercise.primaryMuscleGroup {
                                Text(group)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search exercises")
            .navigationTitle("Add Exercise")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New Exercise") { showingAddCustom = true }
                }
            }
            .task { await load() }
            .sheet(isPresented: $showingAddCustom) {
                AddCustomExerciseView { exercise in
                    exercises.append(exercise)
                    exercises.sort { $0.name < $1.name }
                    onPick(exercise)
                    dismiss()
                }
            }
        }
    }

    private func load() async {
        do {
            exercises = try await repository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AddCustomExerciseView: View {
    let onCreated: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category = "compound"
    @State private var muscleGroup = ""
    @State private var equipment = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    private let repository = ExerciseRepository()

    private let categories = ["compound", "isolation", "cardio", "mobility"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    TextField("Name", text: $name)
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0.capitalized) }
                    }
                    TextField("Primary Muscle Group (optional)", text: $muscleGroup)
                    TextField("Equipment (optional)", text: $equipment)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("New Exercise")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { Task { await save() } }
                        .disabled(name.isEmpty || isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            let exercise = try await repository.createCustom(
                name: name,
                category: category,
                primaryMuscleGroup: muscleGroup.isEmpty ? nil : muscleGroup,
                equipment: equipment.isEmpty ? nil : equipment
            )
            onCreated(exercise)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
