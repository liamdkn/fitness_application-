import SwiftUI

/// How many of this workout's exercises actually got a set logged, vs how
/// many were part of the session (routine-day planned, or added ad hoc)
/// but never touched - shown on the finish sheet as "X of Y completed, Z
/// skipped." Lays the groundwork for a future rating/penalty on skipping,
/// not scored here - just surfaced.
struct WorkoutCompletionSummary {
    let totalExercises: Int
    let completedExercises: Int
    var skippedExercises: Int { max(0, totalExercises - completedExercises) }
}

struct WorkoutRatingSheet: View {
    let summary: WorkoutCompletionSummary
    let onSave: (Int, String) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rating = 3
    @State private var notes: String
    @State private var isSaving = false

    init(summary: WorkoutCompletionSummary, initialNotes: String, onSave: @escaping (Int, String) async -> Void) {
        self.summary = summary
        self.onSave = onSave
        _notes = State(initialValue: initialNotes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(summary.completedExercises) of \(summary.totalExercises) exercises completed")
                    if summary.skippedExercises > 0 {
                        Text("\(summary.skippedExercises) skipped")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Rate This Workout") {
                    Picker("Rating", selection: $rating) {
                        ForEach(1...5, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                // Whole-workout notes moved here from the live workout
                // screen - a field sitting at the bottom of an in-progress
                // workout went unused; asking for it once, at the natural
                // "how'd that go" moment, is the more honest home for it.
                Section("Notes") {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
            }
            .navigationTitle("Workout Finished")
            // Swipeable, deliberately - realizing you forgot to log a set
            // should be a swipe back to the workout, not a dead end. The
            // workout itself is untouched either way (still running,
            // nothing saved) until Save is actually tapped.
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isSaving = true
                        Task {
                            await onSave(rating, notes)
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
