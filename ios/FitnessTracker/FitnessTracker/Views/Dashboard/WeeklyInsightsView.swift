import Charts
import SwiftUI

/// Which nutrition metric the Nutrition section's daily breakdown/weekly
/// average is currently showing - one picker drives both, so switching
/// tabs swaps the whole card rather than needing four separate ones.
private enum NutritionMacro: String, CaseIterable, Identifiable {
    case calories, protein, carbs, fat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .calories: "Calories"
        case .protein: "Protein"
        case .carbs: "Carbs"
        case .fat: "Fat"
        }
    }

    var unit: String { self == .calories ? "kcal" : "g" }
}

/// One point on the weight chart's projected goal line - see
/// `WeeklyInsightsView.goalLinePoints`.
private struct GoalLinePoint: Identifiable {
    let date: Date
    let weightKg: Double
    var id: Date { date }
}

struct WeeklyInsightsView: View {
    /// When set (e.g. a row tapped in Weekly Log), opens straight to that
    /// week instead of the current one - Weekly Log is the at-a-glance
    /// index, this is where the "why" for any given week lives.
    var initialWeekStart: Date?

    @StateObject private var viewModel = WeeklyInsightsViewModel()
    @StateObject private var weekPickerViewModel = WeeklyLogViewModel()
    @State private var isWeekPickerExpanded = false
    @State private var selectedNutritionMacro: NutritionMacro = .calories

    private func dailyEntries(for macro: NutritionMacro) -> [DailyMacroEntry] {
        switch macro {
        case .calories: viewModel.dailyCalories
        case .protein: viewModel.dailyProtein
        case .carbs: viewModel.dailyCarbs
        case .fat: viewModel.dailyFat
        }
    }

    private func target(for macro: NutritionMacro) -> Double? {
        switch macro {
        case .calories: viewModel.goal?.dailyCalorieTarget
        case .protein: viewModel.goal?.proteinGTarget
        case .carbs: viewModel.goal?.carbsGTarget
        case .fat: viewModel.goal?.fatGTarget
        }
    }

    private func weeklyAverage(for macro: NutritionMacro) -> Double? {
        switch macro {
        case .calories: viewModel.avgCaloriesPerDay
        case .protein: viewModel.avgProteinPerDay
        case .carbs: viewModel.avgCarbsPerDay
        case .fat: viewModel.avgFatPerDay
        }
    }

    private func formattedWaterAmount(_ ml: Double) -> String {
        ml >= 1000 ? String(format: "%.1f L", ml / 1000) : "\(Int(ml)) ml"
    }

    /// The phase's target weight-loss/gain rate, projected across the
    /// selected Mon-Sun week - the same projection the Dashboard's weight
    /// card used to plot before it was stripped down to a glance card, just
    /// scoped to whichever week is being viewed here instead of always
    /// "now."
    private var goalLinePoints: [GoalLinePoint] {
        guard let goal = viewModel.goal,
              let startingWeightKg = goal.startingWeightKg,
              let weeklyRate = goal.weeklyWeightChangeKg,
              let phaseStart = ISO8601DateFormatter().date(from: goal.phaseStartedAt + "T00:00:00Z")
        else { return [] }

        let calendar = Calendar.current
        let weekStart = viewModel.selectedWeekStart
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let today = Date()

        func projectedWeight(on date: Date) -> Double {
            let daysSince = calendar.dateComponents([.day], from: phaseStart, to: date).day ?? 0
            return startingWeightKg + weeklyRate / 7 * Double(daysSince)
        }

        // Clipped to the selected week, and never past today (a past week's
        // line runs its full Mon-Sun length; the current week's stops at
        // today rather than projecting into days that haven't happened).
        let lineStart = Swift.max(phaseStart, weekStart)
        let lineEnd = Swift.min(today, weekEnd)
        guard lineEnd >= lineStart else { return [] }

        return [
            GoalLinePoint(date: lineStart, weightKg: projectedWeight(on: lineStart)),
            GoalLinePoint(date: lineEnd, weightKg: projectedWeight(on: lineEnd))
        ]
    }

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
        .appScreen()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    WeeklyLogTableView()
                } label: {
                    Image(systemName: "tablecells")
                }
                .appToolbarTint()
            }
        }
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
    /// this absorbs what used to be the separate Weekly Log list screen, and
    /// is the only way to change weeks (no prev/next chevrons - the dropdown
    /// is the one navigation surface).
    private var weekNavHeader: some View {
        HStack {
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
        }
    }

    @ViewBuilder
    private var weeklyInsightsContent: some View {
            if viewModel.scoreHistory.compactMap(\.overall).count >= 2 {
                Section("Trend") {
                    AdherenceTrendChart(points: viewModel.scoreHistory)
                }
                .listRowBackground(AppRowBackground())
            }

            Section("Adherence Score") {
                WeeklyAdherenceCard(weeklyScore: viewModel.weeklyAdherence)
            }
            .listRowBackground(AppRowBackground())

            if let checkin = viewModel.weeklyCheckin, checkin.hasSurveyContent {
                Section("Weekly Check-In") {
                    WeeklyCheckinSummary(checkin: checkin)
                }
                .listRowBackground(AppRowBackground())
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
                .listRowBackground(AppRowBackground())

                // Avg + breakdown work for any week; the "you need X/day"
                // debt rows only ever populate for the live current week
                // (see `StepsDebt`/`NutritionDebtSummary`'s doc comments),
                // so they simply don't appear on a past week.
                if !viewModel.dailyCalories.isEmpty {
                    Section("Nutrition") {
                        Picker("Macro", selection: $selectedNutritionMacro) {
                            ForEach(NutritionMacro.allCases) { macro in
                                Text(macro.label).tag(macro)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowInsets(EdgeInsets())
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                        .listRowSeparator(.hidden)
                        DailyMacroBreakdown(
                            days: dailyEntries(for: selectedNutritionMacro),
                            target: target(for: selectedNutritionMacro),
                            unit: selectedNutritionMacro.unit,
                            weeklyAverage: weeklyAverage(for: selectedNutritionMacro)
                        )
                        if let nutritionDebt = viewModel.nutritionDebt, nutritionDebt.hasAny {
                            NutritionDebtSummaryView(debt: nutritionDebt)
                        }
                    }
                    .listRowBackground(AppRowBackground())
                }

                if !viewModel.dailySteps.isEmpty {
                    Section("Steps") {
                        DailyStepsBreakdown(days: viewModel.dailySteps, stepTarget: viewModel.goal?.stepTarget)
                        InsightRow(
                            icon: "figure.walk",
                            label: "Avg steps",
                            value: viewModel.avgStepsPerDay.map { "\(Int($0.rounded()))" } ?? "-",
                            target: viewModel.goal?.stepTarget.map { "\($0)" }
                        )
                        if let stepsDebt = viewModel.stepsDebt, let stepTarget = viewModel.goal?.stepTarget {
                            StepsDebtRow(debt: stepsDebt, stepTarget: stepTarget)
                        }
                    }
                    .listRowBackground(AppRowBackground())
                }

                if let avgWaterMlPerDay = viewModel.avgWaterMlPerDay {
                    Section("Hydration") {
                        InsightRow(
                            icon: "drop.fill",
                            label: "Avg water",
                            value: "\(formattedWaterAmount(avgWaterMlPerDay)) per day",
                            target: nil
                        )
                    }
                    .listRowBackground(AppRowBackground())
                }

                Section("Weight") {
                    if let avgThisWeek = viewModel.avgWeightThisWeek {
                        WeeklyWeightHeadline(
                            avgWeightKg: avgThisWeek,
                            isCurrentWeek: viewModel.isCurrentWeek,
                            excludedBumpDays: viewModel.avgWeightThisWeekExcludedBumpDays
                        )
                    }
                    if !viewModel.weekWeights.isEmpty {
                        InteractiveWeeklyWeightChart(weights: viewModel.weekWeights, goalLinePoints: goalLinePoints)
                    }
                    if let avgLastWeek = viewModel.avgWeightLastWeek {
                        InsightRow(
                            icon: "calendar",
                            label: "Last week's average",
                            value: String(format: "%.1f kg", avgLastWeek),
                            target: nil
                        )
                    }
                    if let totalChange = viewModel.totalPhaseWeightChangeKg {
                        InsightRow(
                            icon: totalChange > 0 ? "chart.line.uptrend.xyaxis" : "chart.line.downtrend.xyaxis",
                            label: totalChange < 0 ? "Total lost this phase" : totalChange > 0 ? "Total gained this phase" : "Total change this phase",
                            value: String(format: "%.1f kg", abs(totalChange)),
                            target: nil
                        )
                    }
                }
                .listRowBackground(AppRowBackground())

                if viewModel.isCurrentWeek {
                    Section {
                        MaintenanceCaloriesCard(
                            insight: viewModel.maintenanceInsight,
                            goal: viewModel.goal,
                            completedNutritionDays: viewModel.completedNutritionDays,
                            completedDays: viewModel.completedDaysInSelectedWeek
                        )
                    } header: {
                        Text("Maintenance Calories")
                    }
                    .listRowBackground(AppRowBackground())
                }
            } else if viewModel.isLoading {
                ProgressView()
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(AppColor.error)
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
        .background(AppRowBackground())
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
    let completedNutritionDays: Int
    let completedDays: Int

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
            Text(missingDataMessage)
                .foregroundStyle(.secondary)
        }
    }

    private var missingDataMessage: String {
        if completedDays > 0 && completedNutritionDays < max(3, Int(ceil(Double(completedDays) * 0.8))) {
            return "Food is logged on \(completedNutritionDays) of \(completedDays) completed days. Missing days could change this estimate, so a weekly pace isn't shown."
        }
        return "Log food on at least 5 days each week for 3 weeks, and weigh in regularly, to see your maintenance calorie estimate."
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
        case 85...: return AppColor.success
        case 65..<85: return AppColor.warning
        default: return AppColor.danger
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
                Text("Nutrition logged on \(weeklyScore.nutritionDaysLoggedCount) of \(weeklyScore.elapsedDaysCount) elapsed days")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("The score uses available data from \(weeklyScore.scoredDaysCount) days; missing days are unknown.")
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
        case 85...: return AppColor.success
        case 65..<85: return AppColor.warning
        default: return AppColor.danger
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
                Text("\(dayScore.scoredCount) of \(dayScore.totalCount) metrics scored")
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

/// Monday-Sunday row-per-day steps list - the front-and-center view for
/// "how is this week going," with the average/debt summary below it.
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
        guard let stepTarget, stepTarget > 0 else { return AppColor.steps }
        return steps >= stepTarget ? AppColor.success : AppColor.steps
    }

    private func weekdayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

/// Monday-Sunday row-per-day breakdown for whichever nutrition macro is
/// selected, same layout as `DailyStepsBreakdown` - a plain magnitude bar,
/// not colored by over/under target, since unlike steps a low day isn't
/// universally "good" for calories or any macro. A plain "Avg" text row
/// (value vs. target, no progress bar) sits right under Sunday, matching
/// the Steps section's own "Avg steps" row.
private struct DailyMacroBreakdown: View {
    let days: [DailyMacroEntry]
    let target: Double?
    let unit: String
    let weeklyAverage: Double?

    private var maxValue: Double {
        max(days.compactMap(\.value).max() ?? 0, target ?? 0, 1)
    }

    private func formatted(_ value: Double) -> String {
        unit == "kcal" ? "\(Int(value.rounded())) kcal" : "\(Int(value.rounded()))\(unit)"
    }

    var body: some View {
        VStack(spacing: 8) {
            ForEach(days) { day in
                dayRow(day)
            }
            Divider()
                .padding(.top, 6)
            averageRow
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func dayRow(_ day: DailyMacroEntry) -> some View {
        HStack(spacing: 12) {
            Text(weekdayLabel(day.date))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.15))
                    if let value = day.value {
                        Capsule()
                            .fill(AppColor.steps)
                            .frame(width: geometry.size.width * min(value / maxValue, 1))
                    }
                }
            }
            .frame(height: 8)

            Text(day.value.map(formatted) ?? "-")
                .font(.caption)
                .foregroundStyle(day.value == nil ? .secondary : .primary)
                .frame(width: 72, alignment: .trailing)
                .monospacedDigit()
        }
    }

    private var averageRow: some View {
        HStack {
            Text("Avg")
            Spacer()
            Text(averageText)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }

    private var averageText: String {
        let avgText = weeklyAverage.map(formatted) ?? "-"
        guard let target else { return avgText }
        return "\(avgText) / \(formatted(target))"
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
                    .foregroundStyle(debt.stepsBehindPace < 0 ? AppColor.danger : .secondary)
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
private struct NutritionDebtSummaryView: View {
    let debt: NutritionDebtSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("To Hit This Week's Goal")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
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

/// The big headline number - this week's average weight (or "so far," if
/// the week's still in progress and not every day has a weigh-in yet).
private struct WeeklyWeightHeadline: View {
    let avgWeightKg: Double
    let isCurrentWeek: Bool
    let excludedBumpDays: Int

    var body: some View {
        VStack(spacing: 2) {
            Text(String(format: "%.1f kg", avgWeightKg))
                .font(.system(size: 40, weight: .bold, design: .rounded))
            Text(isCurrentWeek ? "Average so far this week" : "Average this week")
                .font(.caption)
                .foregroundStyle(.secondary)
            if excludedBumpDays > 0 {
                Text("Excludes \(excludedBumpDays) post-off-plan \(excludedBumpDays == 1 ? "reading" : "readings")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}

/// This week's raw weigh-ins plotted across the selected Mon-Sun week, plus
/// the phase's projected goal line - tap or drag over a point to see that
/// day's reading, the same way the Health app's own charts work.
private struct InteractiveWeeklyWeightChart: View {
    let weights: [BodyWeightLog]
    let goalLinePoints: [GoalLinePoint]

    @State private var selectedLog: BodyWeightLog?

    /// A day-to-day weight chart lives in a narrow band (a kg or two), so
    /// letting the axis auto-scale from zero squashes every real move flat
    /// against the top. Centering tightly on the actual readings (plus the
    /// goal line, so it's never clipped) with a little headroom makes the
    /// week's actual movement visible.
    private var yAxisDomain: ClosedRange<Double> {
        let values = weights.map(\.weightKg) + goalLinePoints.map(\.weightKg)
        guard let min = values.min(), let max = values.max() else { return 0...100 }
        guard max > min else { return (min - 1)...(max + 1) }
        let padding = Swift.max((max - min) * 0.2, 0.5)
        return (min - padding)...(max + padding)
    }

    var body: some View {
        Chart {
            ForEach(weights) { log in
                LineMark(
                    x: .value("Date", log.loggedAt),
                    y: .value("Weight (kg)", log.weightKg),
                    series: .value("Series", "Actual")
                )
                .foregroundStyle(AppColor.weight)
                PointMark(
                    x: .value("Date", log.loggedAt),
                    y: .value("Weight (kg)", log.weightKg)
                )
                .foregroundStyle(AppColor.weight)
                .symbolSize(log.id == selectedLog?.id ? 60 : 30)
            }
            ForEach(goalLinePoints) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Weight (kg)", point.weightKg),
                    series: .value("Series", "Goal")
                )
                .foregroundStyle(AppColor.danger.opacity(0.6))
                .lineStyle(StrokeStyle(dash: [5, 3]))
            }
            if let selectedLog {
                RuleMark(x: .value("Date", selectedLog.loggedAt))
                    .foregroundStyle(.secondary.opacity(0.25))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(spacing: 1) {
                            Text(selectedLog.loggedAt, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f kg", selectedLog.weightKg))
                                .font(.caption.bold())
                        }
                        .padding(6)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.weekday(.narrow))
            }
        }
        .chartYScale(domain: yAxisDomain)
        .frame(height: 160)
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in selectNearestLog(at: value.location, proxy: proxy, geometry: geometry) }
                    )
                    .onTapGesture { location in selectNearestLog(at: location, proxy: proxy, geometry: geometry) }
            }
        }
        .padding(.vertical, 4)
    }

    private func selectNearestLog(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let origin = geometry[plotFrame].origin
        let xPosition = location.x - origin.x
        guard let date: Date = proxy.value(atX: xPosition) else { return }
        selectedLog = weights.min { abs($0.loggedAt.timeIntervalSince(date)) < abs($1.loggedAt.timeIntervalSince(date)) }
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
        case 85...: return AppColor.success
        case 65..<85: return AppColor.warning
        default: return AppColor.danger
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
