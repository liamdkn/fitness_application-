import SwiftUI

struct WorkoutRatingSheet: View {
    let onSave: (Int?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rating = 3
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Rate This Workout") {
                    Picker("Rating", selection: $rating) {
                        ForEach(1...5, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

            }
            .navigationTitle("Workout Finished")
            .interactiveDismissDisabled()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Skip") {
                        Task {
                            await onSave(nil)
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isSaving = true
                        Task {
                            await onSave(rating)
                            isSaving = false
                            dismiss()
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }
}
