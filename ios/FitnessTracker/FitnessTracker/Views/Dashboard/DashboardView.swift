import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @StateObject private var watchActivityViewModel = WatchActivityViewModel()
    @State private var activeSheet: DashboardSheet?
    @State private var selectedDate = Date()
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
                    if let todayChecklist = viewModel.todayChecklist {
                        TodayChecklistCard(checklist: todayChecklist)
                    }

                    // Both rows always stay - completing one doesn't make
                    // it un-tappable, since a mistyped number (weight, most
                    // often) is only fixable by reopening the same sheet,
                    // which already loads the saved answers back in.
                    CheckInsCard(
                        dailyCompleted: checkinAvailability.dailyCompletedToday,
                        weeklyCompleted: checkinAvailability.weeklyCompletedThisWeek,
                        onTapDaily: { activeSheet = .dailyCheckin },
                        onTapWeekly: { activeSheet = .weeklyCheckin }
                    )

                    WatchActivityCard(viewModel: watchActivityViewModel)

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
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                if let currentWeightKg = viewModel.currentWeightKg {
                                    Text(String(format: "%.1f kg", currentWeightKg))
                                        .font(.title2.bold())
                                } else {
                                    Text("No weigh-ins yet")
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let weightTrend = viewModel.weightTrend {
                                    WeightTrendBadge(trend: weightTrend)
                                }
                            }
                            if let goalWeightKg = viewModel.goal?.targetWeightKg {
                                Text("Goal: \(String(format: "%.1f", goalWeightKg)) kg")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let excludedText = weightGlanceExclusionText {
                                Text(excludedText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
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
                            NavigationLink("Weigh-In History") {
                                WeightHistoryView()
                            }
                            .font(.caption)
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
                await viewModel.loadWeightGlance()
                await viewModel.loadOffPlanInsights()
                await viewModel.loadTodayChecklist()
                await checkinAvailability.refresh()
                await watchActivityViewModel.loadCandidates()
            }
            .refreshable {
                await viewModel.load(date: selectedDate)
                await viewModel.loadWeightGlance()
                await viewModel.loadOffPlanInsights()
                await viewModel.loadTodayChecklist()
                await checkinAvailability.refresh()
                await watchActivityViewModel.loadCandidates()
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

    private var weightGlanceExclusionText: String? {
        let count = viewModel.weightGlanceExcludedBumpDays
        guard count > 0 else { return nil }
        return "Trend excludes \(count) recent off-plan \(count == 1 ? "day" : "days")"
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
}

private struct CheckInsCard: View {
    let dailyCompleted: Bool
    let weeklyCompleted: Bool
    let onTapDaily: () -> Void
    let onTapWeekly: () -> Void

    var body: some View {
        DashboardCard(title: "Check-Ins") {
            VStack(alignment: .leading, spacing: 12) {
                Button(action: onTapDaily) {
                    checkinRow(label: "Daily Check-In", completed: dailyCompleted)
                }
                .buttonStyle(.plain)

                Divider()
                Button(action: onTapWeekly) {
                    checkinRow(label: "Weekly Check-In", completed: weeklyCompleted)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Tapping a completed row reopens the same sheet, pre-filled with
    /// today's saved answers - the only way to fix something mistyped
    /// earlier (weight, most often) is to edit and re-save it, not to
    /// lose access to the form the moment it's done once.
    @ViewBuilder
    private func checkinRow(label: String, completed: Bool) -> some View {
        HStack {
            Text(label)
            if completed {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
    }
}

/// Opens straight into this week's Weekly Insights (the "why" behind the
/// current week) rather than the week-by-week list screen - Weekly
/// Insights' own header now doubles as that list, via a tappable
/// week-picker that expands in place (see `WeeklyInsightsView.weekNavHeader`).
private struct WeeklyLogLinkCard: View {
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

/// Three green ticks for steps/workout/calories - visual only for now (see
/// `TodayChecklist`'s doc comment), so tapping doesn't do anything yet.
private struct TodayChecklistCard: View {
    let checklist: TodayChecklist

    var body: some View {
        DashboardCard(title: "Today") {
            HStack {
                checklistItem(label: "Steps", done: checklist.stepsHit)
                Spacer()
                checklistItem(label: "Workout", done: checklist.workoutLogged)
                Spacer()
                checklistItem(label: "Calories", done: checklist.caloriesInRange)
            }
        }
    }

    @ViewBuilder
    private func checklistItem(label: String, done: Bool) -> some View {
        VStack(spacing: 4) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(done ? .green : .secondary.opacity(0.4))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WeightTrendBadge: View {
    let trend: WeightTrend

    private var icon: String {
        switch trend {
        case .up: "arrow.up.right"
        case .down: "arrow.down.right"
        case .stable: "arrow.right"
        }
    }

    private var label: String {
        switch trend {
        case .up: "Up"
        case .down: "Down"
        case .stable: "Stable"
        }
    }

    var body: some View {
        Label(label, systemImage: icon)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
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
