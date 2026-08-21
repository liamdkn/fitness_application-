import Charts
import SwiftUI

struct MyGoalsView: View {
    @State private var currentGoal: UserGoal?
    @State private var pastGoals: [UserGoal] = []
    @State private var tdeeHistory: [TDEEEstimate] = []
    @State private var errorMessage: String?
    @State private var showingNewPhase = false
    @State private var showingEditPhase = false
    private let repository = GoalsRepository()
    private let tdeeEstimateRepository = TDEEEstimateRepository()

    var body: some View {
        List {
            Section("Current Phase") {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                } else if let currentGoal {
                    currentPhaseCard(currentGoal)
                    Button("Edit Phase") { showingEditPhase = true }
                } else {
                    Text("No active phase.")
                        .foregroundStyle(.secondary)
                }
                Button("Start New Phase") { showingNewPhase = true }
            }

            if tdeeChartPoints.count >= 2 {
                Section("Estimated Maintenance Calories") {
                    Chart(tdeeChartPoints, id: \.date) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Estimated TDEE", point.tdee)
                        )
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("Estimated TDEE", point.tdee)
                        )
                    }
                    .frame(height: 160)
                    .padding(.vertical, 4)
                    Text("From the adaptive calorie engine's weekly estimates - shows how your true maintenance has drifted over the phase.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if pastGoals.count > 1 {
                Section("Past Phases") {
                    ForEach(pastGoals.dropFirst()) { goal in
                        HStack {
                            Text(goal.phaseType.displayName)
                            Spacer()
                            Text(goal.effectiveFrom)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .navigationTitle("My Goals")
        .task { await load() }
        .sheet(isPresented: $showingNewPhase) {
            StartNewPhaseView { _ in
                Task { await load() }
            }
        }
        .sheet(isPresented: $showingEditPhase) {
            if let currentGoal {
                EditPhaseView(goal: currentGoal) { _ in
                    Task { await load() }
                }
            }
        }
    }

    @ViewBuilder
    private func currentPhaseCard(_ goal: UserGoal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(goal.phaseType.displayName)
                .font(.title2.bold())
            Text("Started \(goal.effectiveFrom) - \(goal.durationWeeks) weeks")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let startingWeightKg = goal.startingWeightKg {
                Text("Starting weight: \(startingWeightKg, specifier: "%.1f") kg")
                    .font(.caption)
            }
            if let rate = goal.weeklyWeightChangeKg, rate != 0 {
                Text("Target rate: \(rate, specifier: "%.2f") kg/week")
                    .font(.caption)
            }
            Divider()
            Text("\(Int(goal.dailyCalorieTarget)) kcal / \(Int(goal.proteinGTarget))g protein")
                .font(.caption)
            if let sessions = goal.cardioSessionsPerWeek, let minutes = goal.cardioMinutesPerSession {
                Text("Cardio: \(sessions)x/week, \(minutes) min")
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }

    private struct TDEEChartPoint {
        let date: Date
        let tdee: Double
    }

    private var tdeeChartPoints: [TDEEChartPoint] {
        tdeeHistory.compactMap { estimate in
            guard let date = DateFormatting.date(fromISODate: estimate.estimatedAt) else { return nil }
            return TDEEChartPoint(date: date, tdee: estimate.estimatedTDEE)
        }
    }

    private func load() async {
        do {
            currentGoal = try await repository.fetchCurrentGoal()
            pastGoals = try await repository.fetchPastGoals()
        } catch {
            errorMessage = error.localizedDescription
        }
        // Advisory only - a missing/broken TDEE table shouldn't block the
        // Current Phase display above.
        tdeeHistory = (try? await tdeeEstimateRepository.fetchHistory()) ?? []
    }
}
