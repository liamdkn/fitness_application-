import SwiftUI

struct WeeklyInsightsView: View {
    @StateObject private var viewModel = WeeklyInsightsViewModel()

    var body: some View {
        List {
            if let summary = viewModel.summary {
                Section("Training") {
                    InsightRow(
                        icon: "dumbbell.fill",
                        label: "Training volume",
                        value: summary.weeklyVolumeKg.map { "\(Int($0)) kg" } ?? "0 kg",
                        target: nil
                    )
                    InsightRow(
                        icon: "figure.run",
                        label: "Cardio sessions",
                        value: "\(summary.cardioSessionsCompleted)",
                        target: viewModel.goal?.cardioSessionsPerWeek.map { "\($0)" }
                    )
                }

                Section("Activity") {
                    if let avgSteps = summary.avgStepsPerLoggedDay {
                        InsightRow(
                            icon: "figure.walk",
                            label: "Avg steps/day",
                            value: "\(avgSteps)",
                            target: viewModel.goal?.stepTarget.map { "\($0)" }
                        )
                    } else {
                        Text("No steps logged this week.")
                            .foregroundStyle(.secondary)
                    }

                    if let debt = viewModel.stepsDebt, let stepTarget = viewModel.goal?.stepTarget {
                        StepsDebtView(debt: debt, stepTarget: stepTarget)
                    }
                }

                Section("Nutrition") {
                    if let avgCalories = summary.avgCaloriesPerLoggedDay {
                        InsightRow(
                            icon: "flame.fill",
                            label: "Avg calories/day",
                            value: "\(Int(avgCalories)) kcal",
                            target: viewModel.goal.map { "\(Int($0.dailyCalorieTarget)) kcal" }
                        )
                        MacroLine(label: "Protein", value: summary.avgProteinG, target: viewModel.goal?.proteinGTarget)
                        MacroLine(label: "Carbs", value: summary.avgCarbsG, target: viewModel.goal?.carbsGTarget)
                        MacroLine(label: "Fat", value: summary.avgFatG, target: viewModel.goal?.fatGTarget)
                    } else {
                        Text("No nutrition logged this week.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Weight") {
                    if let weightChange = summary.weightChangeThisWeekKg {
                        InsightRow(
                            icon: "scalemass.fill",
                            label: "Weight change",
                            value: "\(String(format: "%+.1f", weightChange)) kg",
                            target: viewModel.goal?.weeklyWeightChangeKg.map { "\(String(format: "%+.1f", $0)) kg" }
                        )
                    } else {
                        Text("Not enough weigh-ins this week to show a change.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Adherence Score") {
                    WeeklyAdherenceCard(weeklyScore: viewModel.weeklyAdherence)
                }

                Section {
                    MaintenanceCaloriesCard(insight: viewModel.maintenanceInsight, goal: viewModel.goal)
                } header: {
                    Text("Maintenance Calories")
                }
            } else if viewModel.isLoading {
                ProgressView()
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .navigationTitle("Weekly Insights")
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
    }
}

private struct MaintenanceCaloriesCard: View {
    let insight: MaintenanceInsight?
    let goal: UserGoal?

    var body: some View {
        if let insight {
            VStack(alignment: .leading, spacing: 10) {
                Text("Estimated maintenance: ~\(Int(insight.estimatedTDEE)) kcal/day")
                    .font(.headline)

                Text(balanceSentence(insight))
                    .font(.subheadline)

                if let paceSentence = paceSentence(insight, goal: goal) {
                    Text(paceSentence)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        } else {
            Text("Log your weight and nutrition daily for a couple of weeks to unlock a maintenance calorie estimate.")
                .foregroundStyle(.secondary)
        }
    }

    private func balanceSentence(_ insight: MaintenanceInsight) -> String {
        let direction = insight.surplusOrDeficit >= 0 ? "over" : "under"
        let magnitude = Int(abs(insight.surplusOrDeficit))
        let rateDirection = insight.impliedWeeklyChangeKg >= 0 ? "gaining" : "losing"
        let rateMagnitude = String(format: "%.2f", abs(insight.impliedWeeklyChangeKg))
        return "You're averaging \(Int(insight.avgCaloriesPerDay)) kcal/day this week, about \(magnitude) kcal \(direction) maintenance - on pace for roughly \(rateDirection) \(rateMagnitude) kg/week from diet alone."
    }

    /// Compares the implied rate to the goal's target weekly rate, using the
    /// same sign convention (negative = losing, positive = gaining) so a cut
    /// and a bulk are both handled by the same comparison.
    private func paceSentence(_ insight: MaintenanceInsight, goal: UserGoal?) -> String? {
        guard let goalRate = goal?.weeklyWeightChangeKg, goalRate != 0 else { return nil }
        let ratio = insight.impliedWeeklyChangeKg / goalRate
        let goalRateText = "\(String(format: "%+.2f", goalRate)) kg/week"
        if ratio >= 0.85 && ratio <= 1.15 {
            return "That's right on pace with your \(goalRateText) goal."
        } else if (goalRate < 0 && insight.impliedWeeklyChangeKg > goalRate) || (goalRate > 0 && insight.impliedWeeklyChangeKg < goalRate) {
            return "That's behind your \(goalRateText) goal."
        } else {
            return "That's ahead of your \(goalRateText) goal."
        }
    }
}

/// The week's overall adherence score as a ring (same visual language as
/// the Dashboard's daily one) with a component breakdown, plus a
/// day-by-day row so a bad patch and where it happened are both visible at
/// a glance rather than hidden inside a single number.
private struct WeeklyAdherenceCard: View {
    let weeklyScore: WeeklyAdherenceScore?

    private func bandColor(_ score: Double) -> Color {
        switch score {
        case 85...: return .green
        case 65..<85: return .orange
        default: return .red
        }
    }

    var body: some View {
        if let weeklyScore, let overall = weeklyScore.overall {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 20) {
                    ScoreRingView(score: overall, color: bandColor(overall), diameter: 84, ringWidth: 11)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(weeklyScore.components) { component in
                            HStack {
                                Text(component.component.label)
                                    .font(.caption)
                                Spacer()
                                Text(component.score.map { "\(Int($0.rounded()))" } ?? "-")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(component.score == nil ? .secondary : .primary)
                            }
                        }
                    }
                }
                Divider()
                HStack(spacing: 4) {
                    ForEach(weeklyScore.dailyScores, id: \.date) { day in
                        dayColumn(day)
                    }
                }
            }
            .padding(.vertical, 4)
        } else {
            Text("Log a few days this week to see your weekly adherence score.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func dayColumn(_ day: DailyAdherenceScore) -> some View {
        VStack(spacing: 4) {
            Text(weekdayLetter(day.date))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Circle()
                .fill(day.overall.map(bandColor) ?? Color.secondary.opacity(0.15))
                .frame(width: 26, height: 26)
                .overlay {
                    if let overall = day.overall {
                        Text("\(Int(overall.rounded()))")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
        }
        .frame(maxWidth: .infinity)
    }

    private func weekdayLetter(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date)
    }
}

private struct StepsDebtView: View {
    let debt: StepsDebt
    let stepTarget: Int

    private var paceText: String {
        if debt.completedDays == 0 {
            return "Week just started"
        } else if debt.stepsBehindPace < 0 {
            return "\(-debt.stepsBehindPace) behind pace"
        } else if debt.stepsBehindPace > 0 {
            return "+\(debt.stepsBehindPace) ahead of pace"
        } else {
            return "Right on pace"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Steps debt", systemImage: "figure.walk.motion")
                Spacer()
                Text(paceText)
                    .foregroundStyle(debt.stepsBehindPace < 0 ? .red : .secondary)
            }
            Text("Need \(debt.requiredPerDayForRest)/day through Sunday to still average \(stepTarget) (\(debt.remainingDays) day\(debt.remainingDays == 1 ? "" : "s") left).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

private struct InsightRow: View {
    let icon: String
    let label: String
    let value: String
    let target: String?

    var body: some View {
        HStack {
            Label(label, systemImage: icon)
            Spacer()
            if let target {
                Text("\(value) / \(target)")
            } else {
                Text(value)
            }
        }
    }
}

private struct MacroLine: View {
    let label: String
    let value: Double?
    let target: Double?

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .frame(width: 50, alignment: .leading)
            if let target, target > 0 {
                ProgressView(value: min((value ?? 0) / target, 1))
            } else {
                ProgressView(value: 0)
            }
            Text(macroText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
        }
    }

    private var macroText: String {
        let valueText = value.map { "\(Int($0))g" } ?? "-"
        guard let target else { return valueText }
        return "\(valueText)/\(Int(target))g"
    }
}

#Preview {
    NavigationStack {
        WeeklyInsightsView()
    }
}
