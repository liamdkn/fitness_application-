import SwiftUI

struct WorkoutDetailView: View {
    let workout: Workout

    @State private var dayLabel: String?
    @State private var exerciseNames: [UUID: String] = [:]
    @State private var setsByExercise: [(exerciseId: UUID, sets: [WorkoutSet])] = []
    @State private var errorMessage: String?
    private let workoutRepository = WorkoutRepository()
    private let routineRepository = RoutineRepository()
    private let exerciseRepository = ExerciseRepository()

    var body: some View {
        List {
            Section {
                HStack {
                    Text(workout.performedAt, style: .date)
                    if let duration = workout.duration {
                        Text(formattedDuration(duration))
                    } else {
                        Text("in progress")
                    }
                }
                .foregroundStyle(.secondary)
                if let rating = workout.rating {
                    HStack {
                        Text("Rating")
                        Spacer()
                        Text("\(rating)/5")
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }

            ForEach(setsByExercise, id: \.exerciseId) { entry in
                Section(exerciseNames[entry.exerciseId] ?? "Exercise") {
                    ForEach(entry.sets) { set in
                        HStack {
                            Text("Set \(set.setIndex)")
                            Spacer()
                            Text("\(set.reps) reps \u{00d7} \(set.weightKg, specifier: "%.1f") kg")
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(dayLabel ?? workout.name ?? (workout.routineDayId == nil ? "Open Workout" : "Workout"))
        .task { await load() }
    }

    private func load() async {
        do {
            if let routineDayId = workout.routineDayId {
                dayLabel = try? await routineRepository.fetchDay(id: routineDayId).label
            }
            let sets = try await workoutRepository.fetchSets(workoutId: workout.id)
            let allExercises = try await exerciseRepository.fetchAll()
            exerciseNames = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.id, $0.name) })

            var order: [UUID] = []
            var grouped: [UUID: [WorkoutSet]] = [:]
            for set in sets {
                if grouped[set.exerciseId] == nil {
                    order.append(set.exerciseId)
                }
                grouped[set.exerciseId, default: []].append(set)
            }
            setsByExercise = order.map { ($0, grouped[$0] ?? []) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formattedDuration(_ interval: TimeInterval) -> String {
        "\(Int(interval) / 60) min"
    }
}
