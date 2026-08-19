import Combine
import SwiftUI

struct ActiveWorkoutView: View {
    @StateObject private var viewModel: ActiveWorkoutViewModel
    @State private var showingAddExercise = false
    @State private var showingCancelDialog = false
    @State private var showingRatingSheet = false
    @State private var elapsed: TimeInterval = 0
    @Environment(\.dismiss) private var dismiss

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var supersetLabels: [UUID: String] {
        SupersetLabeling.labels(for: viewModel.activeExercises.compactMap(\.target))
    }

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
                Section {
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

                    SetLogGridView(
                        activeExercise: activeExercise,
                        onLogSet: { reps, weight in
                            Task { await viewModel.logSet(for: activeExercise.id, reps: reps, weightKg: weight) }
                        },
                        onAddSet: {
                            viewModel.addExtraSetRow(for: activeExercise.id)
                        }
                    )
                } header: {
                    HStack {
                        Text(activeExercise.exercise.name)
                        if let groupId = activeExercise.target?.supersetGroupId, let label = supersetLabels[groupId] {
                            Text(label)
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.15), in: Capsule())
                                .foregroundStyle(.blue)
                        }
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

            Section {
                Button {
                    showingRatingSheet = true
                } label: {
                    Text("Finish Workout")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showingCancelDialog = true
                } label: {
                    Text("Cancel Workout")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .listRowBackground(Color.clear)
        }
        .navigationTitle("Workout")
        .navigationBarBackButtonHidden()
        .task { await viewModel.loadTemplate() }
        .onReceive(timer) { _ in
            elapsed = Date().timeIntervalSince(viewModel.workout.startedAt)
        }
        .sheet(isPresented: $showingAddExercise) {
            ExercisePickerView { exercise in
                Task { await viewModel.addAdHocExercise(exercise) }
            }
        }
        .sheet(isPresented: $showingRatingSheet) {
            WorkoutRatingSheet { rating in
                await viewModel.finish(rating: rating)
            }
        }
        .confirmationDialog("Delete this workout? This can't be undone.", isPresented: $showingCancelDialog) {
            Button("Delete Workout", role: .destructive) {
                Task { await viewModel.cancel() }
            }
        }
        .onChange(of: viewModel.isFinished) { _, finished in
            if finished { dismiss() }
        }
        .onChange(of: viewModel.isCancelled) { _, cancelled in
            if cancelled { dismiss() }
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
