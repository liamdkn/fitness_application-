import SwiftUI

/// How many of this workout's exercises actually got a set logged, vs how
/// many were part of the session (routine-day planned, or added ad hoc)
/// but never touched - shown on the paused screen as "X of Y completed, Z
/// skipped." Lays the groundwork for a future rating/penalty on skipping,
/// not scored here - just surfaced.
struct WorkoutCompletionSummary {
    let totalExercises: Int
    let completedExercises: Int
    var skippedExercises: Int { max(0, totalExercises - completedExercises) }
}

/// The paused workout: rate it (and add notes) to save it, or discard it.
/// Reached from the single "Pause Workout" button at the bottom of the live
/// screen. Saving needs a rating; swiping the sheet away (or Resume) goes
/// back to the workout, which is untouched - still running, nothing saved -
/// until Save or Discard is actually tapped.
struct WorkoutRatingSheet: View {
    let summary: WorkoutCompletionSummary
    let onSave: (Int, String) async -> Void
    let onDiscard: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rating: Int?
    @State private var notes: String
    @State private var isWorking = false
    @State private var confirmingDiscard = false

    init(
        summary: WorkoutCompletionSummary,
        initialNotes: String,
        onSave: @escaping (Int, String) async -> Void,
        onDiscard: @escaping () async -> Void
    ) {
        self.summary = summary
        self.onSave = onSave
        self.onDiscard = onDiscard
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
                .listRowBackground(AppRowBackground())

                Section {
                    Picker("Rating", selection: $rating) {
                        ForEach(1...5, id: \.self) { value in
                            Text("\(value)").tag(Optional(value))
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                } header: {
                    Text("Rate This Workout")
                } footer: {
                    if rating == nil {
                        Text("Pick a rating to save the workout.")
                    }
                }
                .listRowBackground(AppRowBackground())

                // Whole-workout notes live here rather than on the live
                // screen - asked for once, at the natural "how'd that go" moment.
                Section("Notes") {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
                .listRowBackground(AppRowBackground())

                Section {
                    Button {
                        guard let rating else { return }
                        isWorking = true
                        Task {
                            await onSave(rating, notes)
                            isWorking = false
                            dismiss()
                        }
                    } label: {
                        if isWorking {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Save Workout")
                        }
                    }
                    .buttonStyle(.appAccent)
                    .disabled(rating == nil || isWorking)

                    Button {
                        confirmingDiscard = true
                    } label: {
                        Text("Discard Workout")
                    }
                    .buttonStyle(.appDestructive)
                    .disabled(isWorking)

                    Button("Resume Workout") { dismiss() }
                        .frame(maxWidth: .infinity)
                        .disabled(isWorking)
                        .padding(.top, 4)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
            .appScreen()
            .navigationTitle("Workout Paused")
            .confirmationDialog("Discard this workout? Nothing will be saved and this can't be undone.", isPresented: $confirmingDiscard, titleVisibility: .visible) {
                Button("Discard Workout", role: .destructive) {
                    isWorking = true
                    Task {
                        await onDiscard()
                        isWorking = false
                        dismiss()
                    }
                }
            }
        }
    }
}
