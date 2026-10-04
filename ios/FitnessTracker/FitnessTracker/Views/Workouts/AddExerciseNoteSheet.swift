import SwiftUI

/// Reachable from an exercise's "..." menu during an active workout - one
/// note per (workout, exercise), editable in place if one already exists
/// for this session. Distinct from `Workout.notes` (whole-workout); this is
/// what later shows up in that exercise's `ExerciseHistoryView`.
struct AddExerciseNoteSheet: View {
    let workoutId: UUID
    let exerciseId: UUID
    let exerciseName: String

    @Environment(\.dismiss) private var dismiss
    @State private var noteText = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    private let repository = ExerciseNoteRepository()

    var body: some View {
        NavigationStack {
            Form {
                Section("Note for \(exerciseName)") {
                    TextField("e.g. Shoulder was sore on this one", text: $noteText, axis: .vertical)
                        .lineLimit(4...10)
                }
                .listRowBackground(AppRowBackground())
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(AppColor.error)
                }
            }
            .appScreen()
            .navigationTitle("Add Note")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                    .appToolbarTint()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(isSaving)
                    .appToolbarTint()
                }
            }
            .task {
                if let existing = try? await repository.fetchNote(workoutId: workoutId, exerciseId: exerciseId) {
                    noteText = existing.note
                }
            }
        }
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await repository.upsertNote(workoutId: workoutId, exerciseId: exerciseId, note: noteText)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
