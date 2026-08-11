import SwiftUI

struct WorkoutHistoryView: View {
    @State private var workouts: [Workout] = []
    @State private var dayLabels: [UUID: String] = [:]
    @State private var errorMessage: String?
    private let workoutRepository = WorkoutRepository()
    private let routineRepository = RoutineRepository()

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                } else if workouts.isEmpty {
                    Text("No workouts logged yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(workouts) { workout in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(workout.routineDayId.flatMap { dayLabels[$0] } ?? workout.name ?? "Workout")
                            .font(.headline)
                        HStack {
                            Text(workout.performedAt, style: .date)
                            if let duration = workout.duration {
                                Text(formattedDuration(duration))
                            } else {
                                Text("in progress")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("History")
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        do {
            workouts = try await workoutRepository.fetchHistory()
            let routineDayIds = Set(workouts.compactMap(\.routineDayId))
            for dayId in routineDayIds where dayLabels[dayId] == nil {
                if let day = try? await routineRepository.fetchDay(id: dayId) {
                    dayLabels[dayId] = day.label
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formattedDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        return "\(minutes) min"
    }
}
