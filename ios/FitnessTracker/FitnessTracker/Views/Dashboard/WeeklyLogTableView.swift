import Charts
import SwiftUI

/// One week's average weight, for the full-history chart - `nil` weeks
/// (no weigh-ins that week) are simply left out rather than plotted as a
/// gap-filling zero.
private struct WeeklyWeightPoint: Identifiable {
    let date: Date
    let weightKg: Double
    var id: Date { date }
}

/// One metric column in the Weekly Log table - how to pull its goal
/// (from the week's resolved `UserGoal`, nil before any goal existed) and
/// its actual average (straight off the `WeeklyLogEntry` row) side by side.
private struct WeeklyTableColumn {
    let title: String
    let unit: String
    let goal: (UserGoal) -> Double?
    let avg: (WeeklyLogEntry) -> Double?
    /// The same metric, pulled off one expanded day instead of the week's
    /// average - what the week's own `avg` row was actually computed from.
    let daily: (DailyLogRow) -> Double?
}

/// One day inside an expanded week's row - the raw numbers `WeeklyLogEntry`'s
/// average was built from, fetched only when that week is actually expanded
/// (see `WeeklyLogTableView.loadDailyRows`), not for every week up front.
private struct DailyLogRow: Identifiable {
    let date: Date
    let calories: Double?
    let proteinG: Double?
    let carbsG: Double?
    let fatG: Double?
    let steps: Double?
    let weightKg: Double?
    var id: Date { date }
}

/// A Goal -> Avg table across every tracked week, most recent first -
/// Calories/Protein/Carbs/Fat/Steps plus average weight, one row per week.
/// Same shape as the ad-hoc query Liam had run by hand against the DB;
/// this is that same table, living in the app. Reuses
/// `WeeklyLogViewModel`'s existing pagination and goal-resolution rather
/// than fetching anything new - just a different rendering of the same
/// rows `WeekPickerList` (in `WeeklyInsightsView`) already loads.
struct WeeklyLogTableView: View {
    @StateObject private var viewModel = WeeklyLogViewModel()
    /// `.compact` here means landscape (iPhone) - every other screen in
    /// the app is portrait-only, but this table has enough columns that
    /// rotating to see them all at once is worth being the one exception
    /// (see `OrientationLock`).
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private let columns: [WeeklyTableColumn] = [
        WeeklyTableColumn(title: "Calories", unit: "", goal: { $0.dailyCalorieTarget }, avg: { $0.avgCalories }, daily: { $0.calories }),
        WeeklyTableColumn(title: "Protein", unit: "g", goal: { $0.proteinGTarget }, avg: { $0.avgProteinG }, daily: { $0.proteinG }),
        WeeklyTableColumn(title: "Carbs", unit: "g", goal: { $0.carbsGTarget }, avg: { $0.avgCarbsG }, daily: { $0.carbsG }),
        WeeklyTableColumn(title: "Fat", unit: "g", goal: { $0.fatGTarget }, avg: { $0.avgFatG }, daily: { $0.fatG }),
        WeeklyTableColumn(title: "Steps", unit: "", goal: { $0.stepTarget.map(Double.init) }, avg: { $0.avgSteps }, daily: { $0.steps })
    ]

    /// Which week's row is currently dropped down to its 7 daily rows -
    /// one at a time, matching a plain accordion (tapping a different week
    /// collapses whichever was open and expands the new one).
    @State private var expandedWeekStart: Date?
    /// Cached per week so re-tapping an already-fetched week's row doesn't
    /// refetch - cleared only by leaving/re-entering the screen.
    @State private var dailyRowsByWeek: [Date: [DailyLogRow]] = [:]
    @State private var loadingWeekStart: Date?
    private let nutritionRepository = NutritionRepository()
    private let healthRepository = HealthRepository()
    private let bodyWeightRepository = BodyWeightRepository()

    /// Oldest to newest, matching the chat table this mirrors - `entries`
    /// itself comes back most-recent-first (see `WeeklyLogRepository`).
    private var orderedEntries: [WeeklyLogEntry] {
        viewModel.entries.reversed()
    }

    private var weightPoints: [WeeklyWeightPoint] {
        orderedEntries.compactMap { entry in
            entry.avgWeightKg.map { avgWeightKg in
                WeeklyWeightPoint(date: entry.weekStartDate, weightKg: avgWeightKg)
            }
        }
    }

    @State private var selectedWeightPoint: WeeklyWeightPoint?

    private var isLandscape: Bool { verticalSizeClass == .compact }

    @ViewBuilder
    private var tableBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            Divider()
            ForEach(orderedEntries) { entry in
                Button {
                    toggleExpanded(entry)
                } label: {
                    row(for: entry)
                }
                .buttonStyle(.plain)
                if expandedWeekStart == entry.weekStartDate {
                    if loadingWeekStart == entry.weekStartDate {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(dailyRowsByWeek[entry.weekStartDate] ?? []) { day in
                            dailyRow(for: day, goal: viewModel.goal(for: entry))
                        }
                    }
                }
                Divider()
            }
        }
        .padding(.horizontal)
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                if weightPoints.count >= 2 {
                    weightChartSection
                }
                // Landscape has room for every column at once, so the table
                // stretches to fill the screen's full width there instead
                // of sitting in a horizontal scroller - `.frame(maxWidth:
                // .infinity)` on a flexible column would otherwise expand
                // to whatever unbounded width `ScrollView(.horizontal)`
                // proposes, not the actual screen width, which is why this
                // branches instead of just always wrapping in one.
                if isLandscape {
                    tableBody
                } else {
                    ScrollView(.horizontal) {
                        tableBody
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            } else if viewModel.entries.isEmpty {
                Text("No weeks logged yet").foregroundStyle(.secondary)
            }
        }
        .appScreen()
        .navigationTitle("PT Summary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(verticalSizeClass == .compact ? .hidden : .automatic, for: .tabBar)
        .task {
            if viewModel.entries.isEmpty { await viewModel.loadAll() }
        }
        .onAppear {
            OrientationLock.shared.mask = [.portrait, .landscapeLeft, .landscapeRight]
        }
        .onDisappear {
            OrientationLock.shared.mask = .portrait
        }
    }

    /// Every week's average weight across the account's full history -
    /// drag or tap to see any point's exact date/value, same interaction
    /// `InteractiveWeeklyWeightChart` (Weekly Insights' single-week chart)
    /// already uses.
    private var weightChartSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weight Over Time")
                .font(.headline)
            Chart {
                ForEach(weightPoints) { point in
                    LineMark(x: .value("Week", point.date), y: .value("Weight (kg)", point.weightKg))
                        .foregroundStyle(AppColor.weight)
                    PointMark(x: .value("Week", point.date), y: .value("Weight (kg)", point.weightKg))
                        .foregroundStyle(AppColor.weight)
                        .symbolSize(point.id == selectedWeightPoint?.id ? 60 : 30)
                }
                if let selectedWeightPoint {
                    RuleMark(x: .value("Week", selectedWeightPoint.date))
                        .foregroundStyle(.secondary.opacity(0.25))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            VStack(spacing: 1) {
                                Text(selectedWeightPoint.date, format: .dateTime.day().month(.abbreviated))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.1f kg", selectedWeightPoint.weightKg))
                                    .font(.caption.bold())
                            }
                            .padding(6)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                        }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                }
            }
            .chartYScale(domain: weightYAxisDomain)
            // The selected-point callout anchors `position: .top` with
            // vertical overflow resolution disabled, so without this the
            // callout can render above the plot area entirely and collide
            // with the "Weight Over Time" title sitting right above the
            // chart - this reserves headroom inside the chart's own frame
            // for it to render into instead. The horizontal padding is
            // separate - without it, the oldest/newest week's point sits
            // flush against the plot area's own edge, right at (or past)
            // the visible frame boundary.
            .chartPlotStyle { plotArea in
                plotArea.padding(.top, 32).padding(.horizontal, 14)
            }
            .frame(height: 180)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in selectNearestWeightPoint(at: value.location, proxy: proxy, geometry: geometry) }
                        )
                        .onTapGesture { location in selectNearestWeightPoint(at: location, proxy: proxy, geometry: geometry) }
                }
            }
        }
        .padding(.horizontal)
    }

    /// A week-to-week weight chart can span a much narrower band than the
    /// default zero-based scale would show - centering tightly on the
    /// actual readings (with a little headroom) keeps real movement
    /// visible instead of squashed flat, same reasoning
    /// `InteractiveWeeklyWeightChart` uses for its own y-axis.
    private var weightYAxisDomain: ClosedRange<Double> {
        let values = weightPoints.map(\.weightKg)
        guard let min = values.min(), let max = values.max() else { return 0...100 }
        guard max > min else { return (min - 1)...(max + 1) }
        let padding = Swift.max((max - min) * 0.15, 0.5)
        return (min - padding)...(max + padding)
    }

    private func selectNearestWeightPoint(at location: CGPoint, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else { return }
        let origin = geometry[plotFrame].origin
        let xPosition = location.x - origin.x
        guard let date: Date = proxy.value(atX: xPosition) else { return }
        selectedWeightPoint = weightPoints.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    /// Fixed-width in portrait (the table scrolls horizontally to fit
    /// every column); flexible/`maxWidth: .infinity` in landscape, where
    /// `tableBody` renders without a horizontal scroller so this actually
    /// stretches to the screen's real width instead of an unbounded one.
    @ViewBuilder
    private func column<Content: View>(fixedWidth: CGFloat, alignment: Alignment, @ViewBuilder content: () -> Content) -> some View {
        if isLandscape {
            content().frame(maxWidth: .infinity, alignment: alignment)
        } else {
            content().frame(width: fixedWidth, alignment: alignment)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 16) {
            column(fixedWidth: 84, alignment: .leading) { Text("Week") }
            ForEach(columns, id: \.title) { column in
                self.column(fixedWidth: 84, alignment: .center) { Text(column.title) }
            }
            column(fixedWidth: 72, alignment: .center) { Text("Weight") }
        }
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .padding(.vertical, 8)
    }

    private func row(for entry: WeeklyLogEntry) -> some View {
        let goal = viewModel.goal(for: entry)
        return HStack(spacing: 16) {
            column(fixedWidth: 84, alignment: .leading) {
                Text(weekLabel(for: entry)).font(.subheadline.weight(.medium))
            }

            ForEach(columns, id: \.title) { column in
                self.column(fixedWidth: 84, alignment: .center) {
                    cell(goal: goal.flatMap(column.goal), avg: column.avg(entry), unit: column.unit)
                }
            }

            column(fixedWidth: 72, alignment: .center) { weightCell(entry) }
        }
        .padding(.vertical, 10)
        // Without this, only the actual rendered glyphs (not the padding/
        // gaps between them) are tappable - this makes the whole row a
        // single hit target instead of a handful of tiny text-shaped ones.
        .contentShape(Rectangle())
    }

    /// One expanded day's row - same columns/widths as `row(for:)`, just
    /// pulling each metric straight off that day instead of the week's
    /// average, and indented so it visually nests under the week it
    /// belongs to.
    private func dailyRow(for day: DailyLogRow, goal: UserGoal?) -> some View {
        HStack(spacing: 16) {
            column(fixedWidth: 84, alignment: .leading) {
                Text(dayLabel(day.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(columns, id: \.title) { column in
                self.column(fixedWidth: 84, alignment: .center) {
                    cell(goal: goal.flatMap(column.goal), avg: column.daily(day), unit: column.unit)
                }
            }

            column(fixedWidth: 72, alignment: .center) {
                VStack(spacing: 2) {
                    Text(" ").font(.caption2)
                    Text(day.weightKg.map { String(format: "%.1f kg", $0) } ?? "-")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.leading, 12)
        .background(Color.secondary.opacity(0.06))
    }

    private func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d"
        return formatter.string(from: date)
    }

    private func toggleExpanded(_ entry: WeeklyLogEntry) {
        let weekStart = entry.weekStartDate
        if expandedWeekStart == weekStart {
            expandedWeekStart = nil
            return
        }
        expandedWeekStart = weekStart
        guard dailyRowsByWeek[weekStart] == nil else { return }
        Task { await loadDailyRows(weekStart: weekStart) }
    }

    /// The 7 days (Mon-Sun) a week's average was actually computed from -
    /// fetched only once a week's row is expanded, not for every week up
    /// front. Same three sources `WeeklyInsightsViewModel.load()` reads for
    /// its own daily breakdowns, just scoped to this one week.
    private func loadDailyRows(weekStart: Date) async {
        loadingWeekStart = weekStart
        defer { if loadingWeekStart == weekStart { loadingWeekStart = nil } }
        let calendar = Calendar.current
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart

        async let nutritionResult = try? nutritionRepository.fetchDailyTotals(from: weekStart, to: weekEnd)
        async let stepLogsResult = try? healthRepository.fetchStepLogs(from: weekStart, to: weekEnd)
        async let weightsResult = try? bodyWeightRepository.fetchRange(from: weekStart, to: weekEnd)

        let nutritionByDate = Dictionary(uniqueKeysWithValues: (await nutritionResult ?? []).map { ($0.date, $0) })
        let stepsByDate = Dictionary(uniqueKeysWithValues: (await stepLogsResult ?? []).map { ($0.date, $0.stepCount) })
        let weights = await weightsResult ?? []
        let weightsByDate = Dictionary(grouping: weights) { calendar.startOfDay(for: $0.loggedAt) }
            .mapValues { average($0.map(\.weightKg)) }

        var rows: [DailyLogRow] = []
        for offset in 0..<7 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { continue }
            let isoDate = DateFormatting.isoDate(date)
            let nutrition = nutritionByDate[isoDate]
            rows.append(DailyLogRow(
                date: date,
                calories: nutrition?.calories,
                proteinG: nutrition?.proteinG,
                carbsG: nutrition?.carbsG,
                fatG: nutrition?.fatG,
                steps: stepsByDate[isoDate].map(Double.init),
                weightKg: weightsByDate[calendar.startOfDay(for: date)] ?? nil
            ))
        }
        dailyRowsByWeek[weekStart] = rows
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }


    @ViewBuilder
    private func cell(goal: Double?, avg: Double?, unit: String) -> some View {
        VStack(spacing: 2) {
            Text(goal.map { formatted($0) + unit } ?? "-")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(avg.map { formatted($0) + unit } ?? "-")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(avg.map { adherenceColor(goal: goal, avg: $0) } ?? .secondary)
        }
    }

    @ViewBuilder
    private func weightCell(_ entry: WeeklyLogEntry) -> some View {
        VStack(spacing: 2) {
            Text(" ").font(.caption2)
            Text(entry.avgWeightKg.map { String(format: "%.1f kg", $0) } ?? "-")
                .font(.subheadline.weight(.semibold))
        }
    }

    /// Green within 5% of goal, orange more than 15% off either way -
    /// purely an at-a-glance signal, not a strict pass/fail (unlike
    /// `NutritionDebtSummaryView`, this has no notion of a running debt).
    private func adherenceColor(goal: Double?, avg: Double) -> Color {
        guard let goal, goal > 0 else { return .primary }
        let ratio = avg / goal
        if abs(ratio - 1) <= 0.05 { return AppColor.success }
        return (ratio > 1.15 || ratio < 0.85) ? AppColor.warning : .primary
    }

    private func formatted(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }

    private func weekLabel(for entry: WeeklyLogEntry) -> String {
        if Calendar.current.isDate(entry.weekStartDate, equalTo: WeeklyInsightsViewModel.mondayOfWeek(containing: Date()), toGranularity: .day) {
            return "This Week"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: entry.weekStartDate)
    }
}
