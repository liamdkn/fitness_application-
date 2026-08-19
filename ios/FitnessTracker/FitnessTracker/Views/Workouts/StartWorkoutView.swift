import SwiftUI

struct StartWorkoutView: View {
    @State private var routine: Routine?
    @State private var todayDay: RoutineDay?
    @State private var isRestDay = false
    @State private var days: [RoutineDay] = []
    @State private var errorMessage: String?
    @State private var startedWorkout: Workout?
    @State private var isStarting = false
    @ObservedObject private var cardioMonitor = CardioSessionMonitor.shared
    private let routineRepository = RoutineRepository()
    private let workoutRepository = WorkoutRepository()
    private let checkinRepository = DailyCheckinRepository()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }

                    if routine == nil {
                        Text("Set up your split to get started.")
                            .foregroundStyle(.secondary)
                        NavigationLink("Set Up My Split") {
                            RoutineEditorView()
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        if let todayDay {
                            Text(todayDay.label)
                                .font(.largeTitle.bold())
                        } else if isRestDay {
                            Text("Rest")
                                .font(.largeTitle.bold())
                        } else {
                            Text("Add a day to your split first.")
                                .foregroundStyle(.secondary)
                        }

                        if isRestDay {
                            Text("Rest day - no workout scheduled.")
                                .foregroundStyle(.secondary)
                        } else if todayDay != nil {
                            Button {
                                Task { await startWorkout() }
                            } label: {
                                if isStarting {
                                    ProgressView()
                                } else {
                                    Text("Start Today's Workout")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isStarting)
                        }

                        if !days.isEmpty {
                            Divider()

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Your Split")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                ForEach(days) { day in
                                    NavigationLink {
                                        RoutineDayDetailView(day: day)
                                    } label: {
                                        HStack {
                                            Text(day.label)
                                            Spacer()
                                            if todayDay?.id == day.id {
                                                Text("Today")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        NavigationLink("Edit My Split") {
                            RoutineEditorView()
                        }
                        .font(.footnote)
                    }

                    DashboardCard(title: "Cardio") {
                        VStack(alignment: .leading, spacing: 12) {
                            if let activeSession = cardioMonitor.activeSession {
                                NavigationLink {
                                    CardioSessionLiveView(session: activeSession)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Cardio Session In Progress")
                                                .fontWeight(.semibold)
                                            Text("\(activeSession.cardioType.displayName) - Tap to Resume")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                }
                            } else {
                                NavigationLink("Start Cardio Session") {
                                    StartCardioSessionView()
                                }
                            }
                            NavigationLink("Cardio History") {
                                CardioHistoryView()
                            }
                            .font(.footnote)
                        }
                    }

                    Divider()

                    WorkoutHistoryView()
                }
                .padding()
            }
            .navigationTitle("Train")
            .task { await load() }
            .navigationDestination(item: $startedWorkout) { workout in
                ActiveWorkoutView(workout: workout)
            }
        }
    }

    private func load() async {
        do {
            let activeRoutine = try await routineRepository.fetchActiveRoutine()
            routine = activeRoutine
            guard let activeRoutine else { return }
            days = try await routineRepository.fetchDays(routineId: activeRoutine.id)

            if let checkin = try await checkinRepository.fetch(date: Date()) {
                if let routineDayId = checkin.routineDayId {
                    todayDay = days.first { $0.id == routineDayId }
                    isRestDay = false
                } else {
                    todayDay = nil
                    isRestDay = true
                }
            } else {
                todayDay = try await workoutRepository.nextRoutineDay(routineId: activeRoutine.id)
                isRestDay = false
            }

            if let todayDay {
                let exercises = try await routineRepository.fetchDayExercises(routineDayId: todayDay.id)
                if exercises.isEmpty {
                    isRestDay = true
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        await CardioSessionMonitor.shared.refresh()
    }

    private func startWorkout() async {
        guard let todayDay else { return }
        isStarting = true
        defer { isStarting = false }
        do {
            startedWorkout = try await workoutRepository.startWorkout(routineDayId: todayDay.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
