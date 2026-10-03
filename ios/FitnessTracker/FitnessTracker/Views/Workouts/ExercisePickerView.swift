import SwiftUI

struct ExercisePickerView: View {
    let onPick: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var listViewModel = ExerciseListViewModel()
    @State private var showingAddCustom = false

    var body: some View {
        NavigationStack {
            ExerciseListContent(listViewModel: listViewModel) { exercise in
                Button {
                    onPick(exercise)
                    dismiss()
                } label: {
                    ExerciseRowContent(exercise: exercise)
                }
            }
            .appScreen()
            .navigationTitle("Add Exercise")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New Exercise") { showingAddCustom = true }
                }
            }
            .sheet(isPresented: $showingAddCustom) {
                AddCustomExerciseView { exercise in
                    listViewModel.addCustom(exercise)
                    onPick(exercise)
                    dismiss()
                }
            }
        }
    }
}

/// Not private - also reused by `ExerciseLibraryView`'s own "New Exercise"
/// entry point.
struct AddCustomExerciseView: View {
    let onCreated: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var category = "compound"
    @State private var muscleGroup: MuscleGroup = .chest
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
                        .textInputAutocapitalization(.words)
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0.capitalized) }
                    }
                    Picker("Primary Muscle Group", selection: $muscleGroup) {
                        ForEach(MuscleGroup.allCases) { group in
                            Text(group.displayName).tag(group)
                        }
                    }
                    TextField("Equipment (optional)", text: $equipment)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(AppColor.error)
                }
            }
            .appScreen()
            .navigationTitle("New Exercise")
            .scrollDismissesKeyboard(.interactively)
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
                name: name.capitalized,
                category: category,
                primaryMuscleGroup: muscleGroup.rawValue,
                equipment: equipment.isEmpty ? nil : equipment
            )
            onCreated(exercise)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
