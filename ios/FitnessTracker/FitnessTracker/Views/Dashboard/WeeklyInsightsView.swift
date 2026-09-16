import Charts
import SwiftUI

struct WeeklyInsightsView: View {
    /// When set (e.g. a row tapped in Weekly Log), opens straight to that
    /// week instead of the current one - Weekly Log is the at-a-glance
    /// index, this is where the "why" for any given week lives.
    var initialWeekStart: Date?

    @StateObject private var viewModel = WeeklyInsightsViewModel()
    @StateObject private var weekPickerViewModel = WeeklyLogViewModel()
    @State private var isWeekPickerExpanded = false

    private var weekRangeLabel: String {
        if viewModel.isCurrentWeek { return "This Week" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let start = viewModel.selectedWeekStart
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Outside the List deliberately - two Buttons sharing one List
            // row has repeatedly misattributed taps in this app (see
            // SetLogGridView, the nutrition date header), and it's exactly
            // the failure mode "flicking" through weeks quickly would
            // expose. Dashboard's day-changer uses the same plain-HStack
            // pattern outside any List for the same reason.
            weekNavHeader
                .padding(.horizontal)
                .padding(.vertical, 12)

            if isWeekPickerExpanded {
                WeekPickerList(viewModel: weekPickerViewModel, selectedWeekStart: viewModel.selectedWeekStart) { weekStart in
                    viewModel.selectWeek(startingAt: weekStart)
                    withAnimation { isWeekPickerExpanded = false }
                }
            }

            List {
                weeklyInsightsContent
            }
            .refreshable { await viewModel.load() }
        }
        .navigationTitle("Weekly Insights")
        .task {
            if let initialWeekStart {
                viewModel.selectWeek(startingAt: initialWeekStart)
            } else {
                await viewModel.load()
            }
        }
    }

    /// Tapping the week label expands it into a scrollable list of every
    /// past week (oldest to newest, phase-labeled) to jump to directly -
    /// this absorbs what used to be the separate Weekly Log list screen, so
    /// the prev/next chevrons only need to step one week at a time.
    private var weekNavHeader: some View {
        HStack {
            Button {
                viewModel.goToPreviousWeek()
            } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Button {
                if weekPickerViewModel.entries.isEmpty {
                    Task { await weekPickerViewModel.loadInitial() }
                }
                withAnimation { isWeekPickerExpanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(weekRangeLabel)
                        .font(.headline)
                    Image(systemName: isWeekPickerExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Button {
                viewModel.goToNextWeek()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(viewModel.isCurrentWeek)
        }
    }

    @ViewBuilder
    private var weeklyInsightsContent: some View {
            if viewModel.scoreHistory.compactMap(\.overall).count >= 2 {
                Section("Trend") {
                    AdherenceTrendChart(points: viewModel.scoreHistory)
                }
            }

            Section("Adherence Score") {
                WeeklyAdherenceCard(weeklyScore: viewModel.weeklyAdherence)
            }

            if let checkin = viewModel.weeklyCheckin, checkin.hasSurveyContent {
                Section("Weekly Check-In") {
                    WeeklyCheckinSummary(checkin: checkin)
                }
            }

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

                // Avg + breakdown work for any week; the "you need X/day"
                // debt rows only ever populate for the live current week
                // (see `StepsDebt`/`NutritionDebtSummary`'s doc comments),
                // so they simply don't appear on a past week.
                if !viewModel.dailyCalories.isEmpty {
                    Section("Nutrition") {
                        WeeklyNutritionAveragesView(
                            avgCalories: viewModel.avgCaloriesPerDay,
                            avgProtein: viewModel.avgProteinPerDay,
                            avgCarbs: viewModel.avgCarbsPerDay,
                            avgFat: viewModel.avgFatPerDay,
                            goal: viewModel.goal
                        )
                        if let nutritionDebt = viewModel.nutritionDebt, nutritionDebt.hasAny {
                            NutritionDebtSummaryView(debt: nutritionDebt)
                        }
                        DisclosureGroup("Daily Breakdown") {
                            DailyCaloriesBreakdown(days: viewModel.dailyCalories, calorieTarget: viewModel.goal?.dailyCalorieTarget)
                        }
                    }
                }

                if !viewModel.dailySteps.isEmpty {
                    Section("Steps") {
                        InsightRow(
                            icon: "figure.walk",
                            label: "Avg steps",
                            value: viewModel.avgStepsPerDay.map { "\(Int($0.rounded()))" } ?? "-",
                            target: viewModel.goal?.stepTarget.map { "\($0)" }
                        )
                        if let stepsDebt = viewModel.stepsDebt, let stepTarget = viewModel.goal?.stepTarget {
                            StepsDebtRow(debt: stepsDebt, stepTarget: stepTarget)
                        }
                        DisclosureGroup("Daily Breakdown") {
                            DailyStepsBreakdown(days: viewModel.dailySteps, stepTarget: viewModel.goal?.stepTarget)
                        }
                    }
                }

                Section("Weight") {
                    if !viewModel.weekWeights.isEmpty {
                        WeeklyWeightChart(weights: viewModel.weekWeights)
                    }
                    if let avgThisWeek = viewModel.avgWeightThisWeek {
                        WeightAverageComparisonRow(
                            avgThisWeek: avgThisWeek,
                            avgLastWeek: viewModel.avgWeightLastWeek,
                            trend: viewModel.weightTrendVsLastWeek
                        )
                    }
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
                    NavigationLink("Weigh-In History") {
                        WeightHistoryView()
                    }
                    .font(.footnote)
                }

                if viewModel.isCurrentWeek {
                    Section {
                        MaintenanceCaloriesCard(insight: viewModel.maintenanceInsight, goal: viewModel.goal)
                    } header: {
                        Text("Maintenance Calories")
                    }
                }
            } else if viewModel.isLoading {
                ProgressView()
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
    }
}

/// The expanded week list under the tappable header - reuses
/// `WeeklyLogViewModel`'s existing pagination and phase-label logic
/// (formerly the whole of the standalone Weekly Log screen), displayed
/// oldest to newest with "This Week" standing in for the current row.
private struct WeekPickerList: View {
    @ObservedObject var viewModel: WeeklyLogViewModel
    let selectedWeekStart: Date
    let onSelect: (Date) -> Void

    private var orderedEntries: [WeeklyLogEntry] {
        viewModel.entries.reversed()
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(orderedEntries) { entry in
                    Button {
                        onSelect(entry.weekStartDate)
                    } label: {
                        HStack {
                            Text(label(for: entry))
                            Spacer()
                            if Calendar.current.isDate(entry.weekStartDate, equalTo: selectedWeekStart, toGranularity: .day) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 10)
                        .padding(.horizontal)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .task {
                        await viewModel.loadMoreIfNeeded(currentEntry: entry)
                    }
                    Divider()
                }
                if viewModel.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
        }
        .frame(maxHeight: 280)
        .background(.background.secondary)
    }

    private func label(for entry: WeeklyLogEntry) -> String {
        if Calendar.current.isDate(entry.weekStartDate, equalTo: WeeklyInsightsViewModel.mondayOfWeek(containing: Date()), toGranularity: .day) {
            return "This Week"
        }
        return viewModel.phaseLabel(for: entry) ?? weekRangeText(entry.weekStartDate)
    }

    private func weekRangeText(_ start: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
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

    /// Which day's breakdown is expanded inline below the strip - tapping
    /// the same day again collapses it, tapping another swaps to it.
    @State private var selectedDay: DailyAdherenceScore?

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
                Text("\(weeklyScore.scoredCount) of \(weeklyScore.totalCount) tracked this week")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Divider()
                HStack(spacing: 4) {
                    ForEach(weeklyScore.dailyScores, id: \.date) { day in
                        dayColumn(day)
                    }
                }
                Text("Tap a day to see its details.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if let selectedDay {
                    Divider()
                    DayAdherenceInlineDetail(dayScore: selectedDay)
                }
            }
            .padding(.vertical, 4)
        } else {
            Text("Log a few days this week to see your weekly adherence score.")
                .foregroundStyle(.secondary)
        }
    }

    // Plain tap gestures rather than Buttons/NavigationLinks - several
    // interactive controls sharing one List row has repeatedly misattributed
    // taps in this app (each day here is a sibling in one shared row), and a
    // bare tap gesture per view doesn't fight over that row's hit-testing
    // the way stacked Buttons do.
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
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                selectedDay = (selectedDay == day) ? nil : day
            }
        }
    }

    private func weekdayLetter(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date)
    }
}

/// A selected day's adherence breakdown, shown inline under the day strip
/// instead of pushing a new screen - flicking between a few days' detail
/// shouldn't cost a navigation round trip each time.
private struct DayAdherenceInlineDetail: View {
    let dayScore: DailyAdherenceScore

    private var titleText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: dayScore.date)
    }

    private func bandColor(_ score: Double) -> Color {
        switch score {
        case 85...: return .green
        case 65..<85: return .orange
        default: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(titleText)
                    .font(.subheadline.bold())
                Spacer()
                if let overall = dayScore.overall {
                    Text("\(Int(overall.rounded()))")
                        .font(.subheadline.bold())
                        .foregroundStyle(bandColor(overall))
                }
            }
            if dayScore.overall == nil {
                Text("Not enough logged this day for a score.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(dayScore.scoredCount) of \(dayScore.totalCount) tracked")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            ForEach(dayScore.components) { component in
                HStack {
                    Text(component.component.label)
                        .font(.caption)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(component.score.map { "\(Int($0.rounded()))" } ?? "-")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(component.score == nil ? .secondary : .primary)
                        Text(component.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

/// Monday-Sunday row-per-day steps list, shown inside a `DisclosureGroup` so
/// it doesn't crowd the summary numbers above it by default.
private struct DailyStepsBreakdown: View {
    let days: [DailyStepEntry]
    let stepTarget: Int?

    private var maxSteps: Int {
        max(days.compactMap(\.steps).max() ?? 0, stepTarget ?? 0, 1)
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(days) { day in
                dayRow(day)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func dayRow(_ day: DailyStepEntry) -> some View {
        HStack(spacing: 12) {
            Text(weekdayLabel(day.date))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    if let steps = day.steps {
                        Capsule()
                            .fill(barColor(steps))
                            .frame(width: geometry.size.width * min(Double(steps) / Double(maxSteps), 1))
                    }
                }
            }
            .frame(height: 8)

            Text(day.steps.map { "\($0)" } ?? "-")
                .font(.caption)
                .foregroundStyle(day.steps == nil ? .secondary : .primary)
                .frame(width: 56, alignment: .trailing)
                .monospacedDigit()
        }
    }

    private func barColor(_ steps: Int) -> Color {
        guard let stepTarget, stepTarget > 0 else { return .blue }
        return steps >= stepTarget ? .green : .blue
    }

    private func weekdayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

/// Monday-Sunday row-per-day calories list, same layout as
/// `DailyStepsBreakdown` - a plain magnitude bar, not colored by over/under
/// target, since unlike steps a low calorie day isn't universally "good."
private struct DailyCaloriesBreakdown: View {
    let days: [DailyCalorieEntry]
    let calorieTarget: Double?

    private var maxCalories: Double {
        max(days.compactMap(\.calories).max() ?? 0, calorieTarget ?? 0, 1)
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(days) { day in
                dayRow(day)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func dayRow(_ day: DailyCalorieEntry) -> some View {
        HStack(spacing: 12) {
            Text(weekdayLabel(day.date))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    if let calories = day.calories {
                        Capsule()
                            .fill(Color.blue)
                            .frame(width: geometry.size.width * min(calories / maxCalories, 1))
                    }
                }
            }
            .frame(height: 8)

            Text(day.calories.map { "\(Int($0.rounded()))" } ?? "-")
                .font(.caption)
                .foregroundStyle(day.calories == nil ? .secondary : .primary)
                .frame(width: 56, alignment: .trailing)
                .monospacedDigit()
        }
    }

    private func weekdayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

/// "You need X/day..." for the current week's step target - only ever
/// shown when `viewModel.stepsDebt` is non-nil, which only happens for the
/// live current week (see `StepsDebt`'s doc comment).
private struct StepsDebtRow: View {
    let debt: StepsDebt
    let stepTarget: Int

    private var paceText: String {
        if debt.stepsBehindPace < 0 {
            return "\(-debt.stepsBehindPace) behind pace"
        } else if debt.stepsBehindPace > 0 {
            return "+\(debt.stepsBehindPace) ahead of pace"
        } else {
            return "Right on pace"
        }
    }

    private var subtitleText: String {
        guard debt.remainingDays > 0 else { return "Week complete." }
        return "Need \(debt.requiredPerDayForRest)/day through Sunday to still average \(stepTarget)."
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

/// "You need X/day..." for calories and each macro, to land this week on
/// target - only ever shown for the live current week (see
/// `NutritionDebtSummary`'s doc comment).
/// This week's average calories/protein/carbs/fat against target, as
/// progress bars - same `ProgressView`-per-macro layout as the Dashboard's
/// own "today" macro bars, just averaged over the week instead of one day.
private struct WeeklyNutritionAveragesView: View {
    let avgCalories: Double?
    let avgProtein: Double?
    let avgCarbs: Double?
    let avgFat: Double?
    let goal: UserGoal?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            macroLine(label: "Calories", value: avgCalories, target: goal?.dailyCalorieTarget, unit: "kcal")
            macroLine(label: "Protein", value: avgProtein, target: goal?.proteinGTarget, unit: "g")
            macroLine(label: "Carbs", value: avgCarbs, target: goal?.carbsGTarget, unit: "g")
            macroLine(label: "Fat", value: avgFat, target: goal?.fatGTarget, unit: "g")
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func macroLine(label: String, value: Double?, target: Double?, unit: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .frame(width: 60, alignment: .leading)
            if let target, target > 0 {
                ProgressView(value: min((value ?? 0) / target, 1))
            } else {
                ProgressView(value: 0)
            }
            Text(macroText(value: value, target: target, unit: unit))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
        }
    }

    private func formatted(_ value: Double, unit: String) -> String {
        unit == "kcal" ? "\(Int(value.rounded())) kcal" : "\(Int(value.rounded()))\(unit)"
    }

    private func macroText(value: Double?, target: Double?, unit: String) -> String {
        let valueText = value.map { formatted($0, unit: unit) } ?? "-"
        guard let target else { return valueText }
        return "\(valueText)/\(formatted(target, unit: unit))"
    }
}

private struct NutritionDebtSummaryView: View {
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
        .padding(.vertical, 4)
    }
}

/// One macro's "how much per day for the rest of the week" figure - no
/// ahead/behind-pace framing the way `StepsDebtRow` has, since a low
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
        guard debt.remainingDays > 0 else { return "Week complete." }
        return "Need \(formatted(debt.requiredPerDayForRest))/day through Sunday to average \(formatted(debt.target))."
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

/// This week's raw weigh-ins plotted across the selected Mon-Sun week - a
/// quick "what actually happened" visual to sit above the plainer
/// average/change numbers below it.
private struct WeeklyWeightChart: View {
    let weights: [BodyWeightLog]

    var body: some View {
        Chart {
            ForEach(weights) { log in
                LineMark(
                    x: .value("Date", log.loggedAt),
                    y: .value("Weight (kg)", log.weightKg)
                )
                PointMark(
                    x: .value("Date", log.loggedAt),
                    y: .value("Weight (kg)", log.weightKg)
                )
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.weekday(.narrow))
            }
        }
        .frame(height: 120)
        .padding(.vertical, 4)
    }
}

/// This week's average weight vs last week's, with the same up/down/stable
/// framing as the Dashboard's weight glance card (`WeightTrend`).
private struct WeightAverageComparisonRow: View {
    let avgThisWeek: Double
    let avgLastWeek: Double?
    let trend: WeightTrend?

    private var trendText: String {
        switch trend {
        case .up: "Up"
        case .down: "Down"
        case .stable: "Stable"
        case nil: "-"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("This week's average")
                Spacer()
                Text(String(format: "%.1f kg", avgThisWeek))
                    .fontWeight(.semibold)
            }
            HStack {
                Text("vs last week")
                    .foregroundStyle(.secondary)
                Spacer()
                if let avgLastWeek {
                    Text("\(String(format: "%.1f kg", avgLastWeek)) \u{00B7} \(trendText)")
                        .foregroundStyle(.secondary)
                } else {
                    Text("No data")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
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


/// Multi-week line of `WeeklyAdherenceScore.overall` values, oldest to
/// newest, ending at the selected week - a single week's card can only say
/// "how was this week"; this is the one place the screen answers "is the
/// trend actually moving the right way." Weeks without enough logged data
/// to score (nil) are simply skipped rather than plotted as zero, so a
/// lightly-tracked week reads as a gap, not a crash to the bottom.
private struct AdherenceTrendChart: View {
    let points: [WeeklyScorePoint]

    private func bandColor(_ score: Double) -> Color {
        switch score {
        case 85...: return .green
        case 65..<85: return .orange
        default: return .red
        }
    }

    var body: some View {
        Chart {
            ForEach(points) { point in
                if let overall = point.overall {
                    LineMark(
                        x: .value("Week", point.weekStart),
                        y: .value("Score", overall)
                    )
                    .foregroundStyle(.secondary)
                    .interpolationMethod(.catmullRom)
                    PointMark(
                        x: .value("Week", point.weekStart),
                        y: .value("Score", overall)
                    )
                    .foregroundStyle(bandColor(overall))
                }
            }
        }
        .chartYScale(domain: 0...100)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .frame(height: 110)
        .padding(.vertical, 4)
    }
}

/// A compact, read-only summary of the self-reported `WeeklyCheckin` survey
/// for the selected week - shown right after the objective adherence score
/// so the two can be compared (e.g. a high score next to a self-rated
/// "stressful, low discipline" week is worth noticing on its own). All
/// ratings in `WeeklyCheckinFlow` are 1-5.
struct WeeklyCheckinSummary: View {
    let checkin: WeeklyCheckin

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 20) {
                if let rating = checkin.overallRating7d {
                    ratingStat(label: "Felt like", value: rating)
                }
                if let discipline = checkin.disciplineLevel {
                    ratingStat(label: "Discipline", value: discipline)
                }
                if let stress = checkin.stressLevel {
                    ratingStat(label: "Stress", value: stress)
                }
            }

            if let selfTraining = checkin.trainingAdherence, let selfNutrition = checkin.nutritionAdherence {
                Text("Self-rated adherence: training \(selfTraining)/5, nutrition \(selfNutrition)/5")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let win = checkin.biggestWin, !win.isEmpty {
                Text("Biggest win: \(win)")
                    .font(.subheadline)
            }

            if let notes = checkin.moodNotes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let reason = checkin.stressReason, !reason.isEmpty {
                Text("Stress: \(reason)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func ratingStat(label: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("\(value)/5")
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }
}

#Preview {
    NavigationStack {
        WeeklyInsightsView()
    }
}
