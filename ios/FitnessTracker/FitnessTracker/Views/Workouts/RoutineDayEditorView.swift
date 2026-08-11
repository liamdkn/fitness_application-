import SwiftUI

struct RoutineDayEditorView: View {
    let day: RoutineDay

    @State private var dayExercises: [RoutineDayExercise] = []
    @State private var exerciseNames: [UUID: String] = [:]
    @State private var errorMessage: String?
    @State private var showingPicker = false
    private let routineRepository = RoutineRepository()
    private let exerciseRepository = ExerciseRepository()

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            ForEach(dayExercises) { dayExercise in
                VStack(alignment: .leading, spacing: 4) {
                    Text(exerciseNames[dayExercise.exerciseId] ?? "Exercise")
                        .font(.headline)
                    Text("\(dayExercise.targetSets) sets \u{00d7} \(dayExercise.repRangeLow)-\(dayExercise.repRangeHigh) reps, +\(dayExercise.weightIncrementKg, specifier: "%.1f")kg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onDelete(perform: removeExercises)
        }
        .navigationTitle(day.label)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingPicker = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showingPicker) {
            ExercisePickerView { exercise in
                Task { await addExercise(exercise) }
            }
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

    private func addExercise(_ exercise: Exercise) async {
        exerciseNames[exercise.id] = exercise.name
        do {
            let nextPosition = (dayExercises.map(\.position).max() ?? 0) + 1
            let added = try await routineRepository.addExercise(
                routineDayId: day.id,
                exerciseId: exercise.id,
                position: nextPosition,
                targetSets: 3,
                repRangeLow: 8,
                repRangeHigh: 12,
                weightIncrementKg: 2.5
            )
            dayExercises.append(added)
        } catch {
            errorMessage = error.localizedDescription
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
