import Combine
import SwiftUI

struct ActiveWorkoutView: View {
    @StateObject private var viewModel: ActiveWorkoutViewModel
    @State private var showingAddExercise = false
    @State private var elapsed: TimeInterval = 0
    @Environment(\.dismiss) private var dismiss

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init(workout: Workout) {
        _viewModel = StateObject(wrappedValue: ActiveWorkoutViewModel(workout: workout))
    }

    var body: some View {
        List {
            Section {
                Text(formattedElapsed)
                    .font(.system(.title, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }

            ForEach(viewModel.activeExercises) { activeExercise in
                Section(activeExercise.exercise.name) {
                    if let suggestion = activeExercise.suggestion {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestionHeadline(suggestion))
                                .font(.subheadline.bold())
                            Text(suggestion.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if !activeExercise.previousSets.isEmpty {
                        Text("Last time: " + previousSetsSummary(activeExercise.previousSets))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(activeExercise.loggedSets) { set in
                        HStack {
                            Text("Set \(set.setIndex)")
                            Spacer()
                            Text("\(set.reps) reps \u{00d7} \(set.weightKg, specifier: "%.1f") kg")
                        }
                        .foregroundStyle(.secondary)
                    }

                    SetEntryRow { reps, weight in
                        Task { await viewModel.logSet(for: activeExercise.id, reps: reps, weightKg: weight) }
                    }
                }
            }

            Section {
                Button {
                    showingAddExercise = true
                } label: {
                    Label("Add Exercise", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Workout")
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Finish") {
                    Task { await viewModel.finish() }
                }
                .fontWeight(.semibold)
            }
        }
        .task { await viewModel.loadTemplate() }
        .onReceive(timer) { _ in
            elapsed = Date().timeIntervalSince(viewModel.workout.startedAt)
        }
        .sheet(isPresented: $showingAddExercise) {
            ExercisePickerView { exercise in
                Task { await viewModel.addAdHocExercise(exercise) }
            }
        }
        .onChange(of: viewModel.isFinished) { _, finished in
            if finished { dismiss() }
        }
    }

    private var formattedElapsed: String {
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func suggestionHeadline(_ suggestion: ProgressionSuggestion) -> String {
        if let weight = suggestion.suggestedWeightKg {
            return "Target: \(suggestion.targetReps) reps \u{00d7} \(String(format: "%.1f", weight)) kg"
        } else {
            return "Target: \(suggestion.targetReps) reps"
        }
    }

    private func previousSetsSummary(_ sets: [WorkoutSet]) -> String {
        sets.map { "\($0.reps)\u{00d7}\(String(format: "%.1f", $0.weightKg))kg" }.joined(separator: ", ")
    }
}

private struct SetEntryRow: View {
    let onAdd: (Int, Double) -> Void

    @State private var reps = ""
    @State private var weight = ""

    var body: some View {
        HStack {
            TextField("Reps", text: $reps)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
            TextField("Weight (kg)", text: $weight)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
            Button("Add") {
                guard let repsValue = Int(reps), let weightValue = Double(weight) else { return }
                onAdd(repsValue, weightValue)
                reps = ""
                weight = ""
            }
            .disabled(Int(reps) == nil || Double(weight) == nil)
        }
    }
}
