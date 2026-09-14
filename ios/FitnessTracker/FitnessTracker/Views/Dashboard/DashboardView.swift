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
        case month = "M"
        var id: String { rawValue }

        /// The real calendar period this range anchors to - a Mon-Sun week
        /// or a 1st-to-last-day month containing `anchor` - rather than a
        /// trailing N-days-from-today window, so the chart's X-axis matches
        /// an actual week/month the way Health's does.
        func calendarPeriod(containing anchor: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
            switch self {
            case .week:
                let interval = calendar.dateInterval(of: .weekOfYear, for: anchor) ?? DateInterval(start: anchor, duration: 0)
                return (interval.start, interval.end)
            case .month:
                let interval = calendar.dateInterval(of: .month, for: anchor) ?? DateInterval(start: anchor, duration: 0)
                return (interval.start, interval.end)
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
                    // Hidden entirely once there's nothing left to act on -
                    // daily done and no weekly due - same reasoning that
                    // already keeps the Weekly row hidden until it's due.
                    if !checkinAvailability.dailyCompletedToday || checkinAvailability.weeklyDue {
                        CheckInsCard(
                            dailyCompleted: checkinAvailability.dailyCompletedToday,
                            weeklyDue: checkinAvailability.weeklyDue,
                            onTapDaily: { activeSheet = .dailyCheckin },
                            onTapWeekly: { activeSheet = .weeklyCheckin }
                        )
                    }

                    WeeklyInsightsLinkCard()
                    WeeklyLogLinkCard()

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
                            // Steps/nutrition debt only ever describes the
                            // current week's live pace, so they're gated to
                            // "Today" - showing "debt" alongside a past
                            // day's now-final numbers wouldn't mean anything.
                            if isToday, let nutritionDebt = viewModel.nutritionDebt, nutritionDebt.hasAny {
                                NutritionDebtView(debt: nutritionDebt)
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
                            if isToday, let stepsDebt = viewModel.stepsDebt, let stepTarget = viewModel.goal?.stepTarget {
                                StepsDebtView(debt: stepsDebt, stepTarget: stepTarget)
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
                            .onChange(of: weightChartRange) { _, _ in
                                Task { await loadWeightChart() }
                            }

                            if let summary = weightChartSummaryText {
                                Text(summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
                                    AxisMarks(values: .stride(by: .day, count: weightChartAxisStrideCount)) { _ in
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
                await loadWeightChart()
                await viewModel.loadOffPlanInsights()
                await viewModel.loadCurrentWeekDebts()
                await checkinAvailability.refresh()
            }
            .refreshable {
                await viewModel.load(date: selectedDate)
                await loadWeightChart()
                await viewModel.loadOffPlanInsights()
                await viewModel.loadCurrentWeekDebts()
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

    /// The real calendar date `weightChartPageOffset` weeks/months back
    /// from today - the anchor `calendarPeriod(containing:)` resolves into
    /// the currently-paged week/month.
    private var weightChartPeriod: (start: Date, end: Date) {
        weightChartRange.calendarPeriod(containing: Date())
    }

    private func loadWeightChart() async {
        let period = weightChartPeriod
        await viewModel.loadWeights(from: period.start, to: period.end)
    }

    /// "AVERAGE 71.7 kg" for the month view (matching Health's own M
    /// display), or just the latest reading for the week view (Health's W
    /// view shows the latest value too, not an average).
    private var weightChartSummaryText: String? {
        guard !viewModel.recentWeights.isEmpty else { return nil }
        switch weightChartRange {
        case .week:
            guard let latest = viewModel.recentWeights.last else { return nil }
            return String(format: "%.1f kg", latest.weightKg)
        case .month:
            let weights = viewModel.recentWeights.map(\.weightKg)
            let average = weights.reduce(0, +) / Double(weights.count)
            return String(format: "AVERAGE %.1f kg", average)
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

    private var weightChartAxisStrideCount: Int {
        switch weightChartRange {
        case .week: 1
        case .month: 5
        }
    }

    private var weightChartAxisDateFormat: Date.FormatStyle {
        .dateTime.day().month(.abbreviated)
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

        let today = Date()

        func projectedWeight(on date: Date) -> Double {
            let daysSince = Calendar.current.dateComponents([.day], from: phaseStart, to: date).day ?? 0
            return startingWeightKg + weeklyRate / 7 * Double(daysSince)
        }

        // Clipped to the currently paged week/month - a full-phase goal
        // line (weeks wide) plotted alongside a "W" range's handful of
        // daily points forces Swift Charts to auto-scale the x-axis to fit
        // the wider series, cramming far more daily ticks into the width
        // than it has room for and truncating every label to "...". The
        // line's rate/slope is unaffected - only its visible extent is.
        // Right edge is clipped to `today` too so a past page's line
        // doesn't run past the period it's showing, and a current page
        // mid-week doesn't project into days that haven't happened yet.
        let period = weightChartPeriod
        let lineStart = Swift.max(phaseStart, period.start)
        let lineEnd = Swift.min(today, period.end)
        guard lineEnd >= lineStart else { return [] }

        return [
            GoalLinePoint(date: lineStart, weightKg: projectedWeight(on: lineStart)),
            GoalLinePoint(date: lineEnd, weightKg: projectedWeight(on: lineEnd))
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
                if !dailyCompleted {
                    Button(action: onTapDaily) {
                        checkinRow(label: "Daily Check-In")
                    }
                    .buttonStyle(.plain)
                }

                if weeklyDue {
                    if !dailyCompleted {
                        Divider()
                    }
                    Button(action: onTapWeekly) {
                        checkinRow(label: "Weekly Check-In")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func checkinRow(label: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
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

/// The scannable, week-over-week table - distinct from Weekly Insights (see
/// `WeeklyLogView`'s own doc comment for why these are separate screens).
private struct WeeklyLogLinkCard: View {
    var body: some View {
        DashboardCard {
            NavigationLink {
                WeeklyLogView()
            } label: {
                HStack {
                    Text("Weekly Log")
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

/// Moved here from Weekly Insights - steps debt is inherently a "what do I
/// need today" figure, so it only ever belongs next to today's own steps.
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

    private var subtitleText: String {
        guard debt.remainingDays > 0 else { return "Week complete." }
        return "Need \(debt.requiredPerDayForRest)/day through Sunday to still average \(stepTarget) (\(debt.remainingDays) day\(debt.remainingDays == 1 ? "" : "s") left)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Steps debt", systemImage: "figure.walk.motion")
                Spacer()
                Text(paceText)
                    .foregroundStyle(debt.stepsBehindPace < 0 ? .red : .secondary)
            }
            Text(subtitleText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .padding(.vertical, 2)
    }
}

/// Moved here from Weekly Insights alongside `StepsDebtView`, same reasoning.
private struct NutritionDebtView: View {
    let debt: NutritionDebtSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("To Hit This Week's Goal")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            if let calories = debt.calories {
                MacroDebtRow(debt: calories, label: "Calories", unit: "kcal")
            }
            if let protein = debt.protein {
                MacroDebtRow(debt: protein, label: "Protein", unit: "g")
            }
            if let carbs = debt.carbs {
                MacroDebtRow(debt: carbs, label: "Carbs", unit: "g")
            }
            if let fat = debt.fat {
                MacroDebtRow(debt: fat, label: "Fat", unit: "g")
            }
        }
    }
}

/// One macro's "how much per day for the rest of the week" figure - no
/// ahead/behind-pace framing the way `StepsDebtView` has, since a low
/// number here doesn't universally mean "good" (it can mean "you've
/// already hit your share" just as easily as "ease off, you're over").
private struct MacroDebtRow: View {
    let debt: MacroDebt
    let label: String
    let unit: String

    private func formatted(_ value: Double) -> String {
        unit == "kcal" ? "\(Int(value.rounded())) kcal" : "\(Int(value.rounded()))\(unit)"
    }

    private var text: String {
        if debt.completedDays == 0 { return "Week just started." }
        guard debt.remainingDays > 0 else { return "Week complete." }
        return "Need \(formatted(debt.requiredPerDayForRest))/day through Sunday to average \(formatted(debt.target)) (\(debt.remainingDays) day\(debt.remainingDays == 1 ? "" : "s") left)."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 1)
    }
}

#Preview {
    DashboardView()
}
