import SwiftUI

struct RoutineDayEditorView: View {
    let day: RoutineDay

    @State private var dayExercises: [RoutineDayExercise] = []
    @State private var exerciseNames: [UUID: String] = [:]
    @State private var errorMessage: String?
    @State private var showingPicker = false
    @State private var pendingExercise: Exercise?
    @State private var editingDayExercise: RoutineDayExercise?
    @State private var isLinking = false
    @State private var selectedForLink: Set<UUID> = []
    private let routineRepository = RoutineRepository()
    private let exerciseRepository = ExerciseRepository()

    private var supersetLabels: [UUID: String] {
        SupersetLabeling.labels(for: dayExercises)
    }

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(AppColor.error)
            }
            ForEach(dayExercises) { dayExercise in
                row(for: dayExercise)
            }
            .onDelete(perform: isLinking ? nil : { offsets in removeExercises(at: offsets) })
            .onMove(perform: isLinking ? nil : { source, destination in moveExercises(from: source, to: destination) })
        }
        .appScreen()
        .navigationTitle(day.label)
        .toolbar { toolbarContent }
        .task { await load() }
        .sheet(isPresented: $showingPicker) {
            ExercisePickerView { exercise in
                pendingExercise = exercise
            }
        }
        .sheet(item: $pendingExercise) { exercise in
            ExerciseTargetConfigView(exerciseName: exercise.name) { sets, low, high, increment in
                Task { await addExercise(exercise, targetSets: sets, repRangeLow: low, repRangeHigh: high, weightIncrementKg: increment) }
            }
        }
        .sheet(item: $editingDayExercise) { dayExercise in
            ExerciseTargetConfigView(
                exerciseName: exerciseNames[dayExercise.exerciseId] ?? "Exercise",
                initialTargetSets: dayExercise.targetSets,
                initialRepRangeLow: dayExercise.repRangeLow,
                initialRepRangeHigh: dayExercise.repRangeHigh,
                initialWeightIncrementKg: dayExercise.weightIncrementKg
            ) { sets, low, high, increment in
                Task { await updateExercise(dayExercise, targetSets: sets, repRangeLow: low, repRangeHigh: high, weightIncrementKg: increment) }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            EditButton()
        }
        ToolbarItem(placement: .topBarLeading) {
            Button {
                isLinking.toggle()
                selectedForLink = []
            } label: {
                Image(systemName: isLinking ? "link.circle.fill" : "link")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                if isLinking {
                    Task { await pair() }
                } else {
                    showingPicker = true
                }
            } label: {
                if isLinking {
                    Text("Pair")
                } else {
                    Image(systemName: "plus")
                }
            }
            .disabled(isLinking && selectedForLink.count != 2)
        }
    }

    @ViewBuilder
    private func row(for dayExercise: RoutineDayExercise) -> some View {
        let label = dayExercise.supersetGroupId.flatMap { supersetLabels[$0] }

        Button {
            if isLinking {
                toggleSelection(dayExercise.id)
            } else {
                editingDayExercise = dayExercise
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(exerciseNames[dayExercise.exerciseId] ?? "Exercise")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("\(dayExercise.targetSets) sets \u{00d7} \(dayExercise.repRangeLow)-\(dayExercise.repRangeHigh) reps, +\(dayExercise.weightIncrementKg, specifier: "%.1f")kg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let label {
                        Text(label)
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(AppColor.accent.opacity(0.15), in: Capsule())
                            .foregroundStyle(AppColor.accent)
                    }
                }
                Spacer()
                if isLinking {
                    Image(systemName: selectedForLink.contains(dayExercise.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedForLink.contains(dayExercise.id) ? AppColor.accent : .secondary)
                }
            }
        }
        .contextMenu {
            if !isLinking && dayExercise.supersetGroupId != nil {
                Button("Remove from Superset", role: .destructive) {
                    Task { await unpair(dayExercise) }
                }
            }
        }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedForLink.contains(id) {
            selectedForLink.remove(id)
        } else if selectedForLink.count < 2 {
            selectedForLink.insert(id)
        }
    }

    private func load() async {
        do {
            dayExercises = try await routineRepository.fetchDayExercises(routineDayId: day.id)
            let allExercises = try await exerciseRepository.fetchAll()
            exerciseNames = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.id, $0.name) })
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addExercise(
        _ exercise: Exercise,
        targetSets: Int,
        repRangeLow: Int,
        repRangeHigh: Int,
        weightIncrementKg: Double
    ) async {
        exerciseNames[exercise.id] = exercise.name
        do {
            let nextPosition = (dayExercises.map(\.position).max() ?? 0) + 1
            let added = try await routineRepository.addExercise(
                routineDayId: day.id,
                exerciseId: exercise.id,
                position: nextPosition,
                targetSets: targetSets,
                repRangeLow: repRangeLow,
                repRangeHigh: repRangeHigh,
                weightIncrementKg: weightIncrementKg
            )
            dayExercises.append(added)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func updateExercise(
        _ dayExercise: RoutineDayExercise,
        targetSets: Int,
        repRangeLow: Int,
        repRangeHigh: Int,
        weightIncrementKg: Double
    ) async {
        do {
            let updated = try await routineRepository.updateExercise(
                dayExerciseId: dayExercise.id,
                targetSets: targetSets,
                repRangeLow: repRangeLow,
                repRangeHigh: repRangeHigh,
                weightIncrementKg: weightIncrementKg
            )
            if let index = dayExercises.firstIndex(where: { $0.id == updated.id }) {
                dayExercises[index] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func pair() async {
        guard selectedForLink.count == 2 else { return }
        let ids = Array(selectedForLink)
        do {
            let (a, b) = try await routineRepository.pairExercises(dayExerciseIdA: ids[0], dayExerciseIdB: ids[1])
            for updated in [a, b] {
                if let index = dayExercises.firstIndex(where: { $0.id == updated.id }) {
                    dayExercises[index] = updated
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLinking = false
        selectedForLink = []
    }

    private func unpair(_ dayExercise: RoutineDayExercise) async {
        do {
            let updated = try await routineRepository.unpairExercise(dayExerciseId: dayExercise.id)
            if let index = dayExercises.firstIndex(where: { $0.id == updated.id }) {
                dayExercises[index] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Reorders locally first (instant drag feedback), then persists the
    /// whole new order in one call - see `RoutineRepository.reorderExercises`
    /// for why this has to be a single batch rather than N position updates.
    private func moveExercises(from source: IndexSet, to destination: Int) {
        dayExercises.move(fromOffsets: source, toOffset: destination)
        let orderedIds = dayExercises.map(\.id)
        Task {
            do {
                try await routineRepository.reorderExercises(routineDayId: day.id, orderedIds: orderedIds)
            } catch {
                errorMessage = error.localizedDescription
                await load()
            }
        }
    }

    private func removeExercises(at offsets: IndexSet) {
        let toRemove = offsets.map { dayExercises[$0] }
        dayExercises.remove(atOffsets: offsets)
        Task {
            for dayExercise in toRemove {
                try? await routineRepository.removeExercise(dayExerciseId: dayExercise.id)
            }
        }
    }
}
