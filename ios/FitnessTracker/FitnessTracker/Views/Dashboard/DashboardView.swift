import Charts
import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @State private var activeSheet: DashboardSheet?
    @State private var selectedDate = Date()
    @State private var showGoalLine = true
    @State private var weightChartRange: WeightChartRange = .month
    @ObservedObject private var checkinAvailability = CheckinAvailabilityService.shared

    private enum DashboardSheet: String, Identifiable {
        case dailyCheckin, weeklyCheckin
        var id: String { rawValue }
    }

    private enum WeightChartRange: String, CaseIterable, Identifiable {
        case week = "W"
        case twoWeeks = "2W"
        case month = "M"
        case sixMonths = "6M"
        var id: String { rawValue }

        var days: Int {
            switch self {
            case .week: 7
            case .twoWeeks: 14
            case .month: 30
            case .sixMonths: 183
            }
        }
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

                    WeeklyInsightsLinkCard()

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

                    DashboardCard(title: "Weight") {
                        VStack(alignment: .leading, spacing: 12) {
                            if let note = offPlanNoteText {
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let stat = offPlanHistoricalStatText {
                                Text(stat)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Picker("Range", selection: $weightChartRange) {
                                ForEach(WeightChartRange.allCases) { range in
                                    Text(range.rawValue).tag(range)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: weightChartRange) { _, newValue in
                                Task { await viewModel.loadWeights(daysBack: newValue.days) }
                            }

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
                                        .symbolSize(30)
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
                                .chartXAxis {
                                    // Tick density/label format follows the
                                    // selected range, not a fixed format for
                                    // every range - a week's worth of daily
                                    // dots reads fine with a tick every day,
                                    // but the same format crammed across 6
                                    // months of dots would be unreadable, so
                                    // that range steps by month instead.
                                    AxisMarks(values: .stride(by: weightChartAxisUnit, count: weightChartAxisStrideCount)) { _ in
                                        AxisGridLine()
                                        AxisTick()
                                        AxisValueLabel(format: weightChartAxisDateFormat)
                                    }
                                }
                                .frame(height: 140)
                            }
                            if canShowGoalLine {
                                Toggle("Show goal line", isOn: $showGoalLine)
                                    .font(.caption)
                            }

                            NavigationLink("Weigh-In History") {
                                WeightHistoryView()
                            }
                            .font(.footnote)
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
                await viewModel.loadWeights(daysBack: weightChartRange.days)
                await viewModel.loadOffPlanInsights()
                await checkinAvailability.refresh()
            }
            .refreshable {
                await viewModel.load(date: selectedDate)
                await viewModel.loadWeights(daysBack: weightChartRange.days)
                await viewModel.loadOffPlanInsights()
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

    private var offPlanNoteText: String? {
        guard let insight = viewModel.offPlanRecentInsight else { return nil }
        let dayList = ListFormatter.localizedString(byJoining: insight.offPlanDayLabels)
        let deltaText = String(format: "%.1f", insight.deltaKg)
        let trendClause = insight.trendHasMoved ? "" : ", your trend line hasn't moved"
        return "Up \(deltaText)kg vs. trend - off-plan flagged \(dayList); typically water weight, settles in 2-3 days\(trendClause)."
    }

    private var offPlanHistoricalStatText: String? {
        guard let stat = viewModel.offPlanHistoricalStat else { return nil }
        let direction = stat.averageDeltaKg >= 0 ? "+" : ""
        let deltaText = String(format: "%@%.1f", direction, stat.averageDeltaKg)
        return "You're averaging \(deltaText)kg the day after an off-plan flag, based on \(stat.occurrenceCount) times."
    }

    private var weightChartAxisUnit: Calendar.Component {
        weightChartRange == .sixMonths ? .month : .day
    }

    private var weightChartAxisStrideCount: Int {
        switch weightChartRange {
        case .week: 1
        case .twoWeeks: 2
        case .month: 5
        case .sixMonths: 1
        }
    }

    private var weightChartAxisDateFormat: Date.FormatStyle {
        weightChartRange == .sixMonths
            ? .dateTime.month(.abbreviated)
            : .dateTime.day().month(.abbreviated)
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
        // `phaseStartedAt`, not `effectiveFrom` - `startingWeightKg` was
        // captured once at the true start of the phase, so a mid-phase
        // nutrition-target adjustment (a new row with a later
        // `effectiveFrom`) shouldn't yank this projection's anchor forward
        // to today.
        guard let goal = viewModel.goal,
              let startingWeightKg = goal.startingWeightKg,
              let weeklyRate = goal.weeklyWeightChangeKg,
              let phaseStart = ISO8601DateFormatter().date(from: goal.phaseStartedAt + "T00:00:00Z")
        else { return [] }

        let calendar = Calendar.current
        let today = Date()

        func projectedWeight(on date: Date) -> Double {
            let daysSince = calendar.dateComponents([.day], from: phaseStart, to: date).day ?? 0
            return startingWeightKg + weeklyRate / 7 * Double(daysSince)
        }

        // Clipped to the selected chart range - a full-phase goal line
        // (weeks wide) plotted alongside a "W"/"2W" range's handful of
        // daily points forces Swift Charts to auto-scale the x-axis to fit
        // the wider series, cramming far more daily ticks into the width
        // than it has room for and truncating every label to "...". The
        // line's rate/slope is unaffected - only its visible extent is.
        let windowStart = calendar.date(byAdding: .day, value: -weightChartRange.days, to: today) ?? phaseStart
        let lineStart = Swift.max(phaseStart, windowStart)

        return [
            GoalLinePoint(date: lineStart, weightKg: projectedWeight(on: lineStart)),
            GoalLinePoint(date: today, weightKg: projectedWeight(on: today))
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

/// Adherence is scored weekly now (see `WeeklyInsightsView`), not daily -
/// this is just the Dashboard's entry point into that screen.
private struct WeeklyInsightsLinkCard: View {
    var body: some View {
        DashboardCard {
            NavigationLink {
                WeeklyInsightsView()
            } label: {
                HStack {
                    Text("Weekly Insights")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
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
