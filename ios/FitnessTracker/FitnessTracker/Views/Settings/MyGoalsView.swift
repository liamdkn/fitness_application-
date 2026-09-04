import Charts
import SwiftUI

struct MyGoalsView: View {
    @State private var currentGoal: UserGoal?
    @State private var pastGoals: [UserGoal] = []
    @State private var tdeeHistory: [TDEEEstimate] = []
    @State private var recentWeights: [BodyWeightLog] = []
    /// A pending adaptive-TDEE calorie recommendation, if one's ready - see
    /// `refreshNutritionInsight()`. Lives here (next to the maintenance
    /// history it's derived from) rather than on the Dashboard, so "your
    /// target should probably change" surfaces alongside the drift chart
    /// that explains why, instead of interrupting the daily tracking view.
    @State private var nutritionInsight: TDEEEstimate?
    @State private var isApplyingNutritionInsight = false
    @State private var errorMessage: String?
    @State private var showingNewPhase = false
    @State private var showingEditPhase = false
    private let repository = GoalsRepository()
    private let tdeeEstimateRepository = TDEEEstimateRepository()
    private let bodyWeightRepository = BodyWeightRepository()
    private let nutritionRepository = NutritionRepository()
    private let tdeeWindowDays = 21

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

            if nutritionInsight != nil || tdeeChartPoints.count >= 2 {
                Section("Estimated Maintenance Calories") {
                    if let nutritionInsight {
                        NutritionInsightCard(
                            insight: nutritionInsight,
                            isApplying: isApplyingNutritionInsight,
                            onAccept: { Task { await acceptNutritionInsight() } },
                            onDismiss: { Task { await dismissNutritionInsight() } }
                        )
                    }
                    if tdeeChartPoints.count >= 2 {
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
            if let sessions = goal.strengthSessionsPerWeek {
                let optional = goal.strengthOptionalSessions ?? 0
                Text(optional > 0
                    ? "Training: \(sessions)x/week (\(optional) optional)"
                    : "Training: \(sessions)x/week")
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
        recentWeights = (try? await bodyWeightRepository.fetchRecent(days: 30)) ?? []
        await refreshNutritionInsight()
    }

    /// Only recomputes roughly weekly (a fresh estimate replaces a
    /// week-old one); a still-pending recent estimate is just re-shown
    /// rather than recalculated on every load.
    private func refreshNutritionInsight() async {
        guard let currentGoal else {
            nutritionInsight = nil
            return
        }
        do {
            if let latest = try await tdeeEstimateRepository.fetchLatest(),
               let estimatedDate = DateFormatting.date(fromISODate: latest.estimatedAt),
               (Calendar.current.dateComponents([.day], from: estimatedDate, to: Date()).day ?? 99) < 7 {
                nutritionInsight = latest.status == .pending ? latest : nil
                return
            }

            guard let windowStart = Calendar.current.date(byAdding: .day, value: -tdeeWindowDays, to: Date()) else {
                nutritionInsight = nil
                return
            }
            let windowNutrition = try await nutritionRepository.fetchRange(from: windowStart, to: Date())

            guard let recommendation = AdaptiveTDEEEngine.evaluate(
                weightLogs: recentWeights,
                nutritionLogs: windowNutrition,
                goal: currentGoal,
                windowDays: tdeeWindowDays
            ), recommendation.isActionable else {
                nutritionInsight = nil
                return
            }

            nutritionInsight = try await tdeeEstimateRepository.save(recommendation)
        } catch {
            // Advisory only - don't block this screen on it failing.
        }
    }

    private func acceptNutritionInsight() async {
        guard let insight = nutritionInsight, let currentGoal else { return }
        isApplyingNutritionInsight = true
        defer { isApplyingNutritionInsight = false }
        do {
            self.currentGoal = try await repository.applyCalorieAdjustment(
                to: currentGoal,
                newCalorieTarget: insight.recommendedCalorieTarget
            )
            try await tdeeEstimateRepository.updateStatus(id: insight.id, status: .accepted)
            nutritionInsight = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func dismissNutritionInsight() async {
        guard let insight = nutritionInsight else { return }
        do {
            try await tdeeEstimateRepository.updateStatus(id: insight.id, status: .dismissed)
        } catch {
            // Non-critical - the card just won't reappear until the next
            // weekly recompute either way.
        }
        nutritionInsight = nil
    }
}

private struct NutritionInsightCard: View {
    let insight: TDEEEstimate
    let isApplying: Bool
    let onAccept: () -> Void
    let onDismiss: () -> Void

    private var direction: String {
        insight.recommendedCalorieTarget > insight.currentCalorieTarget ? "up" : "down"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Based on the last \(insight.windowDays) days, your calorie target looks like it should move \(direction), from \(Int(insight.currentCalorieTarget)) to \(Int(insight.recommendedCalorieTarget)) kcal.")
                .font(.subheadline)

            Text("Estimated maintenance: ~\(Int(insight.estimatedTDEE)) kcal/day, from \(insight.loggedDaysInWindow) logged days and a trend weight change of \(String(format: "%.2f", insight.trendWeightChangeKgPerWeek)) kg/week.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button(action: onDismiss) {
                    Text("Dismiss")
                }
                .buttonStyle(.bordered)
                .disabled(isApplying)

                Button(action: onAccept) {
                    if isApplying {
                        ProgressView()
                    } else {
                        Text("Apply New Target")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isApplying)
            }
        }
        .padding(.vertical, 4)
    }
}
