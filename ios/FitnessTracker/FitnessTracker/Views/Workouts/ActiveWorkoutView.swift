import Combine
import SwiftUI

struct ActiveWorkoutView: View {
    @StateObject private var viewModel: ActiveWorkoutViewModel
    @State private var showingAddExercise = false
    @State private var showingCancelDialog = false
    @State private var showingRatingSheet = false
    @State private var noteEditingExercise: ActiveExercise?
    @State private var historyExercise: Exercise?
    @State private var elapsed: TimeInterval = 0
    @State private var restRemaining: TimeInterval = 0
    @Environment(\.dismiss) private var dismiss

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// "X of Y completed, Z skipped" for the finish sheet - completed means
    /// at least one set was actually logged, regardless of whether the
    /// exercise came from today's routine day or was added ad hoc mid-session.
    private var completionSummary: WorkoutCompletionSummary {
        WorkoutCompletionSummary(
            totalExercises: viewModel.activeExercises.count,
            completedExercises: viewModel.activeExercises.filter { !$0.loggedSets.isEmpty }.count
        )
    }

    private var supersetLabels: [UUID: String] {
        SupersetLabeling.labels(for: viewModel.activeExercises.compactMap(\.target))
    }

    /// `viewModel.activeExercises` regrouped so a qualifying superset's
    /// members (2+ exercises sharing a group id `supersetLabels` assigned a
    /// badge to) sit together as one entry instead of appearing as separate,
    /// independently-scrollable exercise cards. A non-superset exercise, or
    /// a lone leftover of an unpaired group, is still its own single-entry
    /// group - same as before this existed.
    private var displayGroups: [[ActiveExercise]] {
        var emittedGroups = Set<UUID>()
        var result: [[ActiveExercise]] = []
        for activeExercise in viewModel.activeExercises {
            if let groupId = activeExercise.target?.supersetGroupId, supersetLabels[groupId] != nil {
                guard !emittedGroups.contains(groupId) else { continue }
                emittedGroups.insert(groupId)
                result.append(viewModel.activeExercises.filter { $0.target?.supersetGroupId == groupId })
            } else {
                result.append([activeExercise])
            }
        }
        return result
    }

    init(workout: Workout) {
        _viewModel = StateObject(wrappedValue: ActiveWorkoutViewModel(workout: workout))
    }

    /// Moves the whole display group (a solo exercise, or an entire
    /// superset's members together) up or down by one slot, then persists
    /// the resulting order. `direction` is -1 (up) or 1 (down).
    private func moveGroup(containing exerciseId: UUID, direction: Int) {
        var groups = displayGroups
        guard let groupIndex = groups.firstIndex(where: { group in group.contains { $0.id == exerciseId } }) else { return }
        let newIndex = groupIndex + direction
        guard groups.indices.contains(newIndex) else { return }
        groups.swapAt(groupIndex, newIndex)
        viewModel.activeExercises = groups.flatMap { $0 }
        Task { await viewModel.persistExerciseOrder() }
    }

    private func isFirstGroup(containing exerciseId: UUID) -> Bool {
        displayGroups.first?.contains { $0.id == exerciseId } ?? false
    }

    private func isLastGroup(containing exerciseId: UUID) -> Bool {
        displayGroups.last?.contains { $0.id == exerciseId } ?? false
    }

    @ViewBuilder
    private func moveMenuButtons(for activeExercise: ActiveExercise) -> some View {
        Button {
            moveGroup(containing: activeExercise.id, direction: -1)
        } label: {
            Label("Move Up", systemImage: "arrow.up")
        }
        .disabled(isFirstGroup(containing: activeExercise.id))
        Button {
            moveGroup(containing: activeExercise.id, direction: 1)
        } label: {
            Label("Move Down", systemImage: "arrow.down")
        }
        .disabled(isLastGroup(containing: activeExercise.id))
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

            ForEach(Array(displayGroups.enumerated()), id: \.offset) { _, group in
                if group.count > 1, let groupId = group.first?.target?.supersetGroupId {
                    supersetSection(group: group, groupId: groupId)
                } else if let activeExercise = group.first {
                    exerciseSection(activeExercise)
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
        .scrollDismissesKeyboard(.interactively)
        // A floating overlay rather than a List section - a Section that
        // pops in when rest starts and back out the moment it ends (which
        // tends to land right as the next set is about to be logged)
        // reflowed every row below it and shifted the scroll position at
        // exactly the wrong moment, causing mistaps on the wrong set's
        // checkmark. An overlay never touches row layout, so it can't do
        // that regardless of timing.
        .safeAreaInset(edge: .bottom) {
            if restRemaining > 0 {
                RestTimerBanner(
                    text: formattedRestRemaining,
                    onSkip: { viewModel.skipRestTimer() }
                )
            }
        }
        .navigationTitle("Workout")
        .navigationBarBackButtonHidden()
        .task { await viewModel.loadTemplate() }
        .onReceive(timer) { _ in
            elapsed = Date().timeIntervalSince(viewModel.workout.startedAt)
            if let restTimerEndDate = viewModel.restTimerEndDate {
                let remaining = restTimerEndDate.timeIntervalSinceNow
                if remaining <= 0 {
                    viewModel.skipRestTimer()
                    restRemaining = 0
                } else {
                    restRemaining = remaining
                }
            } else {
                restRemaining = 0
            }
        }
        .sheet(isPresented: $showingAddExercise) {
            ExercisePickerView { exercise in
                Task { await viewModel.addAdHocExercise(exercise) }
            }
        }
        .sheet(isPresented: $showingRatingSheet) {
            WorkoutRatingSheet(summary: completionSummary, initialNotes: viewModel.workout.notes ?? "") { rating, notes in
                await viewModel.finish(rating: rating, notes: notes)
            }
        }
        .sheet(item: $noteEditingExercise) { activeExercise in
            AddExerciseNoteSheet(
                workoutId: viewModel.workout.id,
                exerciseId: activeExercise.id,
                exerciseName: activeExercise.exercise.name
            )
        }
        .navigationDestination(item: $historyExercise) { exercise in
            ExerciseHistoryView(exercise: exercise)
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

    @ViewBuilder
    private func exerciseContext(for activeExercise: ActiveExercise) -> some View {
        if let muscleGroup = activeExercise.exercise.primaryMuscleGroup,
           viewModel.activeInjuryMuscleGroups.contains(muscleGroup) {
            Label("You've logged an active \(MuscleGroup(rawValue: muscleGroup)?.displayName ?? muscleGroup.capitalized) injury - go easy here.", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
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
                .foregroundStyle(.primary.opacity(0.75))
        }
    }

    @ViewBuilder
    private func supersetBadge(_ label: String) -> some View {
        Text(label)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.blue.opacity(0.15), in: Capsule())
            .foregroundStyle(.blue)
    }

    @ViewBuilder
    private func exerciseSection(_ activeExercise: ActiveExercise) -> some View {
        Section {
            exerciseContext(for: activeExercise)
            SetLogGridView(
                activeExercise: activeExercise,
                onLogSet: { reps, weight, rpe, isDropSet in
                    logSet(exerciseId: activeExercise.id, reps: reps, weight: weight, rpe: rpe, isDropSet: isDropSet)
                },
                onUnlogSet: { set in unlogSet(exerciseId: activeExercise.id, set: set) },
                onAddSet: { addSet(exerciseId: activeExercise.id) },
                onAddDrop: { addDrop(exerciseId: activeExercise.id) },
                onRemoveSetRow: { pendingIndex in removeSetRow(exerciseId: activeExercise.id, pendingIndex: pendingIndex) }
            )
        } header: {
            HStack {
                Text(activeExercise.exercise.name)
                Spacer()
                Menu {
                    moveMenuButtons(for: activeExercise)
                    Button {
                        noteEditingExercise = activeExercise
                    } label: {
                        Label("Add Note", systemImage: "note.text")
                    }
                    Button {
                        historyExercise = activeExercise.exercise
                    } label: {
                        Label("View History", systemImage: "chart.bar.doc.horizontal")
                    }
                    Button("Remove From Workout", role: .destructive) {
                        Task { await viewModel.removeExercise(exerciseId: activeExercise.id) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    /// A qualifying superset (2+ members sharing a group id) renders as one
    /// combined card - both exercises' "last time"/suggestion context
    /// stacked at the top, then a single alternating "A1, B1, A2, B2..."
    /// grid via `SupersetLogGridView` instead of two separate exercise
    /// cards you'd otherwise have to scroll between mid-set.
    @ViewBuilder
    private func supersetSection(group: [ActiveExercise], groupId: UUID) -> some View {
        Section {
            ForEach(group) { activeExercise in
                exerciseContext(for: activeExercise)
            }
            SupersetLogGridView(
                members: group.enumerated().map { index, activeExercise in
                    SupersetMember(
                        activeExercise: activeExercise,
                        movementLetter: movementLetter(at: index),
                        onLogSet: { reps, weight, rpe, isDropSet in
                            logSet(exerciseId: activeExercise.id, reps: reps, weight: weight, rpe: rpe, isDropSet: isDropSet)
                        },
                        onUnlogSet: { set in unlogSet(exerciseId: activeExercise.id, set: set) },
                        onAddDrop: { addDrop(exerciseId: activeExercise.id) },
                        onRemoveSetRow: { pendingIndex in removeSetRow(exerciseId: activeExercise.id, pendingIndex: pendingIndex) }
                    )
                },
                onAddRound: {
                    for activeExercise in group {
                        addSet(exerciseId: activeExercise.id)
                    }
                }
            )
        } header: {
            HStack {
                Text(group.map(\.exercise.name).joined(separator: " + "))
                if let label = supersetLabels[groupId] {
                    supersetBadge(label)
                }
                Spacer()
                Menu {
                    if let first = group.first {
                        moveMenuButtons(for: first)
                    }
                    ForEach(group) { activeExercise in
                        Menu(activeExercise.exercise.name) {
                            Button {
                                noteEditingExercise = activeExercise
                            } label: {
                                Label("Add Note", systemImage: "note.text")
                            }
                            Button {
                                historyExercise = activeExercise.exercise
                            } label: {
                                Label("View History", systemImage: "chart.bar.doc.horizontal")
                            }
                            Button("Remove From Workout", role: .destructive) {
                                Task { await viewModel.removeExercise(exerciseId: activeExercise.id) }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private func movementLetter(at index: Int) -> String {
        String(Character(UnicodeScalar(65 + index % 26)!))
    }

    private func logSet(exerciseId: UUID, reps: Int, weight: Double, rpe: Double?, isDropSet: Bool) {
        Task {
            await viewModel.logSet(for: exerciseId, reps: reps, weightKg: weight, rpe: rpe, isDropSet: isDropSet)
        }
    }

    private func unlogSet(exerciseId: UUID, set: WorkoutSet) {
        Task { await viewModel.unlogSet(for: exerciseId, set: set) }
    }

    private func addSet(exerciseId: UUID) {
        viewModel.addExtraSetRow(for: exerciseId)
    }

    private func addDrop(exerciseId: UUID) {
        viewModel.addDropSetRow(for: exerciseId)
    }

    private func removeSetRow(exerciseId: UUID, pendingIndex: Int) {
        viewModel.removeSetRow(for: exerciseId, at: pendingIndex)
    }

    private var formattedElapsed: String {
        let minutes = Int(elapsed) / 60
        let seconds = Int(elapsed) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private var formattedRestRemaining: String {
        let total = Int(restRemaining.rounded(.up))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "Rest %d:%02d", minutes, seconds)
    }

    private func suggestionHeadline(_ suggestion: ProgressionSuggestion) -> String {
        if let weight = suggestion.suggestedWeightKg {
            return "Target: \(suggestion.targetReps) reps \u{00d7} \(formattedWeight(weight)) kg"
        } else {
            return "Target: \(suggestion.targetReps) reps"
        }
    }

    private func previousSetsSummary(_ sets: [WorkoutSet]) -> String {
        sets.map { "\($0.reps)\u{00d7}\(formattedWeight($0.weightKg))kg" }.joined(separator: ", ")
    }

    private func formattedWeight(_ weightKg: Double) -> String {
        weightKg.formatted(.number.precision(.fractionLength(0...2)))
    }
}

private struct RestTimerBanner: View {
    let text: String
    let onSkip: () -> Void

    var body: some View {
        HStack {
            Label(text, systemImage: "timer")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(.blue)
            Spacer()
            Button("Skip", action: onSkip)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.bar)
    }
}
