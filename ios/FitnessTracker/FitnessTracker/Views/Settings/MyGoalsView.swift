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
    @State private var showingAdjustPhase = false
    @State private var phaseGroupToCancel: PhaseGroup?
    @State private var isCancelingPhase = false
    private let repository = GoalsRepository()
    private let tdeeEstimateRepository = TDEEEstimateRepository()
    private let bodyWeightRepository = BodyWeightRepository()
    private let nutritionRepository = NutritionRepository()
    private let dailyCheckinRepository = DailyCheckinRepository()
    private let tdeeWindowDays = 21

    var body: some View {
        List {
            Section("Current Phase") {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                } else if let currentGoal {
                    currentPhaseCard(currentGoal)
                    Button("Adjust Phase") { showingAdjustPhase = true }
                } else {
                    Text("No active phase.")
                        .foregroundStyle(.secondary)
                }
                Button("Start New Phase") { showingNewPhase = true }
            }

            if !upcomingPhaseGroups.isEmpty {
                Section("Upcoming Phases") {
                    ForEach(upcomingPhaseGroups) { group in
                        upcomingPhaseRow(group)
                    }
                }
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
                        if let latestTDEE = tdeeHistory.last?.estimatedTDEE {
                            VStack(spacing: 2) {
                                Text("\(Int(latestTDEE))")
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                Text("kcal/day estimated maintenance")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 2)
                        }
                        Text("From the adaptive calorie engine's weekly estimates - shows how your true maintenance has drifted over the phase.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !pastPhaseGroups.isEmpty {
                Section("Past Phases") {
                    ForEach(pastPhaseGroups) { group in
                        pastPhaseRow(group)
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
        .sheet(isPresented: $showingAdjustPhase) {
            if let currentGoal {
                AdjustPhaseView(currentGoal: currentGoal) { _ in
                    Task { await load() }
                }
            }
        }
        .confirmationDialog(
            "Cancel this queued phase? This can't be undone.",
            isPresented: Binding(
                get: { phaseGroupToCancel != nil },
                set: { if !$0 { phaseGroupToCancel = nil } }
            )
        ) {
            Button("Cancel Phase", role: .destructive) {
                if let group = phaseGroupToCancel {
                    Task { await cancelUpcomingPhase(group) }
                }
            }
        }
    }

    @ViewBuilder
    private func currentPhaseCard(_ goal: UserGoal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(goal.phaseType.displayName)
                .font(.title2.bold())

            if let daysLeftInPhase {
                VStack(spacing: 2) {
                    Text("\(daysLeftInPhase)")
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                    Text(daysLeftInPhase == 1 ? "day left in this \(goal.phaseType.displayName.lowercased())" : "days left in this \(goal.phaseType.displayName.lowercased())")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }

            if let phaseBrief {
                Text(phaseBrief)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text("Started \(goal.phaseStartedAt)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                if let startingWeightKg = goal.startingWeightKg {
                    phaseDetailRow(icon: "scalemass", label: "Starting Weight", value: String(format: "%.1f kg", startingWeightKg))
                }
                if let rate = goal.weeklyWeightChangeKg, rate != 0 {
                    phaseDetailRow(icon: "chart.line.downtrend.xyaxis", label: "Target Rate", value: String(format: "%.2f kg/week", rate))
                }
                phaseDetailRow(icon: "flame.fill", label: "Calories", value: "\(Int(goal.dailyCalorieTarget)) kcal")
                phaseDetailRow(icon: "fork.knife", label: "Protein", value: "\(Int(goal.proteinGTarget)) g")
                if let sessions = goal.cardioSessionsPerWeek, let minutes = goal.cardioMinutesPerSession {
                    phaseDetailRow(icon: "figure.run", label: "Cardio", value: "\(sessions)x/week, \(minutes) min")
                }
                if let sessions = goal.strengthSessionsPerWeek {
                    let optional = goal.strengthOptionalSessions ?? 0
                    phaseDetailRow(
                        icon: "figure.strengthtraining.traditional",
                        label: "Training",
                        value: optional > 0 ? "\(sessions)x/week (\(optional) optional)" : "\(sessions)x/week"
                    )
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func phaseDetailRow(icon: String, label: String, value: String) -> some View {
        HStack {
            Label(label, systemImage: icon)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
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

    private var daysLeftInPhase: Int? {
        guard let currentGoal,
              currentGoal.durationWeeks > 0,
              let startDate = DateFormatting.date(fromISODate: currentGoal.phaseStartedAt)
        else { return nil }
        let calendar = Calendar.current
        let elapsed = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: startDate),
            to: calendar.startOfDay(for: Date())
        ).day ?? 0
        return max(0, currentGoal.durationWeeks * 7 - elapsed)
    }

    /// Every `user_goals` row that shares the current phase's start date -
    /// each later one is a mid-phase nutrition tweak (see
    /// `AdjustNutritionTargetsView`), not a new phase, so together they're
    /// the full adjustment history of the phase that's currently active.
    private var currentPhaseAdjustments: [UserGoal] {
        guard let currentGoal else { return [] }
        return pastGoals
            .filter { $0.phaseStartedAt == currentGoal.phaseStartedAt }
            .sorted { $0.effectiveFrom < $1.effectiveFrom }
    }

    private var phaseBrief: String? {
        guard let currentGoal, let first = currentPhaseAdjustments.first,
              currentPhaseAdjustments.count > 1
        else { return nil }
        let delta = currentGoal.dailyCalorieTarget - first.dailyCalorieTarget
        let deltaText: String
        if delta < 0 {
            deltaText = "\(Int(-delta)) kcal below where you started"
        } else if delta > 0 {
            deltaText = "\(Int(delta)) kcal above where you started"
        } else {
            deltaText = "back to where you started"
        }
        let adjustmentCount = currentPhaseAdjustments.count - 1
        let times = adjustmentCount == 1 ? "once" : "\(adjustmentCount) times"
        return "Adjusted \(times) since this \(currentGoal.phaseType.displayName.lowercased()) began - now \(deltaText) (\(Int(first.dailyCalorieTarget)) \u{2192} \(Int(currentGoal.dailyCalorieTarget)) kcal)."
    }

    private struct PhaseGroup: Identifiable {
        let phaseStartedAt: String
        let phaseType: GoalPhaseType
        /// Ascending by `effectiveFrom` - every mid-phase adjustment plus
        /// the phase's original starting row.
        let rows: [UserGoal]

        var id: String { phaseStartedAt }
        var initialGoal: UserGoal { rows[0] }
        var finalGoal: UserGoal { rows[rows.count - 1] }
    }

    /// Every distinct phase (grouped by `phaseStartedAt`), current phase
    /// included, oldest first - the basis for both `pastPhaseGroups` and
    /// each past phase's "ended" date (the next group's start).
    private var allPhaseGroups: [PhaseGroup] {
        Dictionary(grouping: pastGoals, by: \.phaseStartedAt)
            .map { phaseStartedAt, rows in
                PhaseGroup(
                    phaseStartedAt: phaseStartedAt,
                    phaseType: rows[0].phaseType,
                    rows: rows.sorted { $0.effectiveFrom < $1.effectiveFrom }
                )
            }
            .sorted { $0.phaseStartedAt < $1.phaseStartedAt }
    }

    private var pastPhaseGroups: [PhaseGroup] {
        guard let currentGoal else { return [] }
        return allPhaseGroups
            .filter { $0.phaseStartedAt != currentGoal.phaseStartedAt && !isUpcoming($0) }
            .reversed()
    }

    /// Phases queued for a future start date - `current_user_goal` won't
    /// pick these up until that date arrives (see its own `effective_from
    /// <= as_of` filter), so until then they're neither the current phase
    /// nor a past one.
    private var upcomingPhaseGroups: [PhaseGroup] {
        allPhaseGroups.filter(isUpcoming)
    }

    private func isUpcoming(_ group: PhaseGroup) -> Bool {
        guard let startDate = DateFormatting.date(fromISODate: group.phaseStartedAt) else { return false }
        let calendar = Calendar.current
        return calendar.startOfDay(for: startDate) > calendar.startOfDay(for: Date())
    }

    private func endLabel(for group: PhaseGroup) -> String {
        let groups = allPhaseGroups
        guard let index = groups.firstIndex(where: { $0.phaseStartedAt == group.phaseStartedAt }),
              index + 1 < groups.count
        else { return "Present" }
        return groups[index + 1].phaseStartedAt
    }

    @ViewBuilder
    private func pastPhaseRow(_ group: PhaseGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(group.phaseType.displayName)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(group.phaseStartedAt) - \(endLabel(for: group))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(macroSummary(group.finalGoal))
                .font(.caption)
            if group.rows.count > 1 {
                Text("Adjusted \(group.rows.count - 1) time\(group.rows.count - 1 == 1 ? "" : "s") - started at \(Int(group.initialGoal.dailyCalorieTarget)) kcal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func upcomingPhaseRow(_ group: PhaseGroup) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(group.phaseType.displayName)
                    .fontWeight(.semibold)
                Spacer()
                Text("Starts \(group.phaseStartedAt)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(macroSummary(group.finalGoal))
                .font(.caption)
            Button("Cancel", role: .destructive) {
                phaseGroupToCancel = group
            }
            .font(.caption)
            .disabled(isCancelingPhase)
        }
        .padding(.vertical, 2)
    }

    private func cancelUpcomingPhase(_ group: PhaseGroup) async {
        isCancelingPhase = true
        defer { isCancelingPhase = false }
        do {
            for row in group.rows {
                try await repository.deleteGoal(id: row.id)
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
        phaseGroupToCancel = nil
    }

    private func macroSummary(_ goal: UserGoal) -> String {
        var parts = ["\(Int(goal.dailyCalorieTarget)) kcal", "P\(Int(goal.proteinGTarget))g"]
        if let carbs = goal.carbsGTarget { parts.append("C\(Int(carbs))g") }
        if let fat = goal.fatGTarget { parts.append("F\(Int(fat))g") }
        return parts.joined(separator: " \u{00b7} ")
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
            let windowCheckins = (try? await dailyCheckinRepository.fetchRecent(days: tdeeWindowDays)) ?? []

            guard let recommendation = AdaptiveTDEEEngine.evaluate(
                weightLogs: recentWeights,
                nutritionLogs: windowNutrition,
                recentCheckins: windowCheckins,
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

    private var excludedBumpDaysClause: String {
        guard insight.excludedBumpDays > 0 else { return "." }
        let noun = insight.excludedBumpDays == 1 ? "day" : "days"
        return " (excludes \(insight.excludedBumpDays) off-plan-affected \(noun))."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Based on the last \(insight.windowDays) days, your calorie target looks like it should move \(direction), from \(Int(insight.currentCalorieTarget)) to \(Int(insight.recommendedCalorieTarget)) kcal.")
                .font(.subheadline)

            Text("Estimated maintenance: ~\(Int(insight.estimatedTDEE)) kcal/day, from \(insight.loggedDaysInWindow) logged days and a trend weight change of \(String(format: "%.2f", insight.trendWeightChangeKgPerWeek)) kg/week\(excludedBumpDaysClause)")
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
