import Combine
import Foundation

struct ActiveExercise: Identifiable {
    let exercise: Exercise
    let target: RoutineDayExercise?
    var previousSets: [WorkoutSet] = []
    var loggedSets: [WorkoutSet] = []

    var id: UUID { exercise.id }

    var suggestion: ProgressionSuggestion? {
        guard let target else { return nil }
        return ProgressionCalculator.suggest(previousSets: previousSets, target: target)
    }
}

@MainActor
final class ActiveWorkoutViewModel: ObservableObject {
    @Published private(set) var workout: Workout
    @Published var activeExercises: [ActiveExercise] = []
    @Published var errorMessage: String?
    @Published var isFinished = false

    private let routineRepository = RoutineRepository()
    private let workoutRepository = WorkoutRepository()
    private let exerciseRepository = ExerciseRepository()

    init(workout: Workout) {
        self.workout = workout
    }

    func loadTemplate() async {
        guard let routineDayId = workout.routineDayId else { return }
        do {
            let dayExercises = try await routineRepository.fetchDayExercises(routineDayId: routineDayId)
            let allExercises = try await exerciseRepository.fetchAll()
            let byId = Dictionary(uniqueKeysWithValues: allExercises.map { ($0.id, $0) })

            for dayExercise in dayExercises {
                guard let exercise = byId[dayExercise.exerciseId] else { continue }
                var active = ActiveExercise(exercise: exercise, target: dayExercise)
                active.previousSets = (try? await workoutRepository.previousSets(exerciseId: exercise.id)) ?? []
                activeExercises.append(active)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addAdHocExercise(_ exercise: Exercise) async {
        guard !activeExercises.contains(where: { $0.id == exercise.id }) else { return }
        var active = ActiveExercise(exercise: exercise, target: nil)
        active.previousSets = (try? await workoutRepository.previousSets(exerciseId: exercise.id)) ?? []
        activeExercises.append(active)
    }

    func logSet(for exerciseId: UUID, reps: Int, weightKg: Double) async {
        guard let index = activeExercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        let nextSetIndex = activeExercises[index].loggedSets.count + 1
        do {
            let set = try await workoutRepository.addSet(
                workoutId: workout.id,
                exerciseId: exerciseId,
                setIndex: nextSetIndex,
                reps: reps,
                weightKg: weightKg,
                rpe: nil,
                isWarmup: false
            )
            activeExercises[index].loggedSets.append(set)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func finish() async {
        do {
            try await workoutRepository.finishWorkout(workoutId: workout.id)
            isFinished = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
