import Charts
import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @State private var activeSheet: DashboardSheet?
    @State private var selectedDate = Date()
    @State private var showGoalLine = true
    @ObservedObject private var checkinAvailability = CheckinAvailabilityService.shared

    private enum DashboardSheet: String, Identifiable {
        case dailyCheckin, weeklyCheckin
        var id: String { rawValue }
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    private var dayTitle: String {
        if isToday { return "Today" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"
        return formatter.string(from: selectedDate)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    CheckInsCard(
                        dailyCompleted: checkinAvailability.dailyCompletedToday,
                        weeklyDue: checkinAvailability.weeklyDue,
                        onTapDaily: { activeSheet = .dailyCheckin },
                        onTapWeekly: { activeSheet = .weeklyCheckin }
                    )

                    DashboardCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Button {
                                    changeDay(by: -1)
                                } label: {
                                    Image(systemName: "chevron.left")
                                }
                                Text(dayTitle)
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Button {
                                    changeDay(by: 1)
                                } label: {
                                    Image(systemName: "chevron.right")
                                }
                                .disabled(isToday)
                            }

                            CalorieRow(nutrition: viewModel.todayNutrition, goal: viewModel.goal)
                            if viewModel.todayNutrition != nil || viewModel.goal != nil {
                                MacroBarsRow(nutrition: viewModel.todayNutrition, goal: viewModel.goal)
                            }
                            Divider()
                            StatRow(
                                icon: "figure.walk",
                                label: "Steps",
                                value: displaySteps.map { "\($0)" } ?? "-",
                                target: viewModel.goal?.stepTarget.map { "\($0)" }
                            )
                            if viewModel.cardioExclusionEnabled, viewModel.cardioStepsExcludedToday > 0 {
                                Text("\(viewModel.cardioStepsExcludedToday) cardio steps excluded")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            StatRow(
                                icon: "bed.double.fill",
                                label: "Sleep last night",
                                value: viewModel.lastNightSleepMinutes.map(formattedDuration) ?? "-",
                                target: viewModel.goal?.sleepTargetMinutes.map(formattedDuration)
                            )
                        }
                    }

                    DashboardCard(title: "This Week") {
                        StatRow(
                            icon: "dumbbell.fill",
                            label: "Training volume",
                            value: viewModel.weeklyVolumeKg.map { "\(Int($0)) kg" } ?? "0 kg",
                            target: nil
                        )
                    }

                    DashboardCard(title: "Weight") {
                        VStack(alignment: .leading, spacing: 12) {
                            if viewModel.recentWeights.isEmpty {
                                Text("No weigh-ins yet.")
                                    .foregroundStyle(.secondary)
                            } else {
                                Chart {
                                    ForEach(viewModel.recentWeights) { log in
                                        LineMark(
                                            x: .value("Date", log.loggedAt),
                                            y: .value("Weight (kg)", log.weightKg),
                                            series: .value("Series", "Actual")
                                        )
                                        .foregroundStyle(by: .value("Series", "Actual"))
                                        PointMark(
                                            x: .value("Date", log.loggedAt),
                                            y: .value("Weight (kg)", log.weightKg)
                                        )
                                        .foregroundStyle(by: .value("Series", "Actual"))
                                    }
                                    if showGoalLine {
                                        ForEach(goalLinePoints) { point in
                                            LineMark(
                                                x: .value("Date", point.date),
                                                y: .value("Weight (kg)", point.weightKg),
                                                series: .value("Series", "Goal")
                                            )
                                            .foregroundStyle(by: .value("Series", "Goal"))
                                            .lineStyle(StrokeStyle(dash: [5, 3]))
                                        }
                                    }
                                }
                                .chartForegroundStyleScale([
                                    "Actual": Color.blue,
                                    "Goal": Color.red.opacity(0.6)
                                ])
                                .chartYScale(domain: weightChartDomain)
                                .frame(height: 140)
                            }
                            if canShowGoalLine {
                                Toggle("Show goal line", isOn: $showGoalLine)
                                    .font(.caption)
                            }
                        }
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .task {
                await viewModel.load(date: selectedDate)
                await checkinAvailability.refresh()
            }
            .refreshable {
                await viewModel.load(date: selectedDate)
                await checkinAvailability.refresh()
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .dailyCheckin:
                    DailyCheckinSheet {
                        await viewModel.load(date: selectedDate)
                    }
                case .weeklyCheckin:
                    WeeklyCheckinFlow {
                        await viewModel.load(date: selectedDate)
                    }
                }
            }
        }
    }

    private func changeDay(by offset: Int) {
        guard let newDate = Calendar.current.date(byAdding: .day, value: offset, to: selectedDate) else { return }
        selectedDate = newDate
        Task { await viewModel.load(date: selectedDate) }
    }

    private func formattedDuration(_ minutes: Int) -> String {
        "\(minutes / 60)h \(minutes % 60)m"
    }

    private var displaySteps: Int? {
        guard let todaySteps = viewModel.todaySteps else { return nil }
        guard viewModel.cardioExclusionEnabled else { return todaySteps }
        return max(todaySteps - viewModel.cardioStepsExcludedToday, 0)
    }

    private var weightChartDomain: ClosedRange<Double> {
        var weights = viewModel.recentWeights.map(\.weightKg)
        if showGoalLine {
            weights.append(contentsOf: goalLinePoints.map(\.weightKg))
        }
        guard let min = weights.min(), let max = weights.max() else { return 0...1 }
        let padding = Swift.max((max - min) * 0.2, 1)
        return (min - padding)...(max + padding)
    }

    private struct GoalLinePoint: Identifiable {
        let date: Date
        let weightKg: Double
        var id: Date { date }
    }

    private var canShowGoalLine: Bool {
        guard let goal = viewModel.goal else { return false }
        return goal.startingWeightKg != nil && goal.weeklyWeightChangeKg != nil
    }

    private var goalLinePoints: [GoalLinePoint] {
        guard let goal = viewModel.goal,
              let startingWeightKg = goal.startingWeightKg,
              let weeklyRate = goal.weeklyWeightChangeKg,
              let startDate = ISO8601DateFormatter().date(from: goal.effectiveFrom + "T00:00:00Z")
        else { return [] }

        let today = Date()
        let daysSince = Calendar.current.dateComponents([.day], from: startDate, to: today).day ?? 0
        let projectedToday = startingWeightKg + weeklyRate / 7 * Double(daysSince)
        return [
            GoalLinePoint(date: startDate, weightKg: startingWeightKg),
            GoalLinePoint(date: today, weightKg: projectedToday)
        ]
    }
}

private struct CheckInsCard: View {
    let dailyCompleted: Bool
    let weeklyDue: Bool
    let onTapDaily: () -> Void
    let onTapWeekly: () -> Void

    var body: some View {
        DashboardCard(title: "Check-Ins") {
            VStack(alignment: .leading, spacing: 12) {
                Button(action: onTapDaily) {
                    checkinRow(label: "Daily Check-In", isDone: dailyCompleted)
                }
                .buttonStyle(.plain)

                if weeklyDue {
                    Divider()
                    Button(action: onTapWeekly) {
                        checkinRow(label: "Weekly Check-In", isDone: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func checkinRow(label: String, isDone: Bool) -> some View {
        HStack {
            Text(label)
            Spacer()
            if isDone {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CalorieRow: View {
    let nutrition: NutritionLog?
    let goal: UserGoal?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Calories", systemImage: "flame.fill")
                Spacer()
                if let nutrition {
                    Text("\(Int(nutrition.calories)) kcal")
                        .fontWeight(.semibold)
                } else {
                    Text("Not logged")
                        .foregroundStyle(.secondary)
                }
            }
            if let goal, let nutrition {
                let remaining = goal.dailyCalorieTarget - nutrition.calories
                Text(remaining >= 0 ? "\(Int(remaining)) kcal remaining" : "\(Int(-remaining)) kcal over")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let goal {
                Text("Goal: \(Int(goal.dailyCalorieTarget)) kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct MacroBarsRow: View {
    let nutrition: NutritionLog?
    let goal: UserGoal?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            macroLine(label: "Protein", value: nutrition?.proteinG, target: goal?.proteinGTarget)
            macroLine(label: "Carbs", value: nutrition?.carbsG, target: goal?.carbsGTarget)
            macroLine(label: "Fat", value: nutrition?.fatG, target: goal?.fatGTarget)
        }
    }

    @ViewBuilder
    private func macroLine(label: String, value: Double?, target: Double?) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .frame(width: 50, alignment: .leading)
            if let target, target > 0 {
                ProgressView(value: min((value ?? 0) / target, 1))
            } else {
                ProgressView(value: 0)
            }
            Text(macroText(value: value, target: target))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
        }
    }

    private func macroText(value: Double?, target: Double?) -> String {
        let valueText = value.map { "\(Int($0))g" } ?? "0g"
        guard let target else { return valueText }
        return "\(valueText)/\(Int(target))g"
    }
}

private struct StatRow: View {
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

#Preview {
    DashboardView()
}
