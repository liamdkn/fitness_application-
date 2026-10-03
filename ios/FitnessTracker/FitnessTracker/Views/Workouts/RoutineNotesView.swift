import SwiftUI

/// The split's "read before training" text - injury constraints, pain and
/// stop rules, retest reminders. Plain text to read and edit; the app never
/// evaluates it (it can't know a pain level or whether a bulge felt hard -
/// those are the user's and their physio's/surgeon's calls).
struct RoutineNotesView: View {
    let routine: Routine
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    private let repository = RoutineRepository()

    init(routine: Routine, onSaved: @escaping () -> Void) {
        self.routine = routine
        self.onSaved = onSaved
        _text = State(initialValue: routine.notes ?? "")
    }

    var body: some View {
        Form {
            Section {
                TextEditor(text: $text)
                    .frame(minHeight: 360)
            } footer: {
                Text("Reference only - the app doesn't track pain or act on any of this.")
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(AppColor.error)
            }
        }
        .appScreen()
        .navigationTitle("Training Notes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { Task { await save() } }
                    .disabled(isSaving || text == (routine.notes ?? ""))
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await repository.updateNotes(routineId: routine.id, notes: text)
            onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
