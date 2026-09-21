import Charts
import SwiftUI

/// One week's average weight, for the full-history chart - `nil` weeks
/// (no weigh-ins that week) are simply left out rather than plotted as a
/// gap-filling zero.
private struct WeeklyWeightPoint: Identifiable {
    let date: Date
    let weightKg: Double
    /// True if any day that week had a check-in flagging the day before it
    /// as off-plan (see `DailyCheckin.yesterdayOffPlan` /
    /// `OffPlanWeightAdvisor`) - a quick "was this week's number affected
    /// by an off-plan day" signal alongside the raw trend line.
    let isOffPlanWeek: Bool
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
        WeeklyTableColumn(title: "Calories", unit: "", goal: { $0.dailyCalorieTarget }, avg: { $0.avgCalories }),
        WeeklyTableColumn(title: "Protein", unit: "g", goal: { $0.proteinGTarget }, avg: { $0.avgProteinG }),
        WeeklyTableColumn(title: "Carbs", unit: "g", goal: { $0.carbsGTarget }, avg: { $0.avgCarbsG }),
        WeeklyTableColumn(title: "Fat", unit: "g", goal: { $0.fatGTarget }, avg: { $0.avgFatG }),
        WeeklyTableColumn(title: "Steps", unit: "", goal: { $0.stepTarget.map(Double.init) }, avg: { $0.avgSteps })
    ]

    /// Oldest to newest, matching the chat table this mirrors - `entries`
    /// itself comes back most-recent-first (see `WeeklyLogRepository`).
    private var orderedEntries: [WeeklyLogEntry] {
        viewModel.entries.reversed()
    }

    private var weightPoints: [WeeklyWeightPoint] {
        orderedEntries.compactMap { entry in
            entry.avgWeightKg.map { avgWeightKg in
                WeeklyWeightPoint(
                    date: entry.weekStartDate,
                    weightKg: avgWeightKg,
                    isOffPlanWeek: weekContainsOffPlanDay(entry.weekStartDate)
                )
            }
        }
    }

    @State private var selectedWeightPoint: WeeklyWeightPoint?
    /// Every day flagged off-plan (start-of-day, `checkinDate - 1`) across
    /// full history - fetched once via `DailyCheckinRepository.
    /// fetchOffPlanDays()`, the same targeted query `OffPlanWeightAdvisor`'s
    /// historical stat already uses, rather than pulling every check-in.
    @State private var offPlanDays: Set<Date> = []
    private let checkinRepository = DailyCheckinRepository()

    private func weekContainsOffPlanDay(_ weekStart: Date) -> Bool {
        let calendar = Calendar.current
        return (0..<7).contains { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return false }
            return offPlanDays.contains(calendar.startOfDay(for: day))
        }
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                if weightPoints.count >= 2 {
                    weightChartSection
                }
                ScrollView(.horizontal) {
                    VStack(alignment: .leading, spacing: 0) {
                        headerRow
                        Divider()
                        ForEach(orderedEntries) { entry in
                            row(for: entry)
                            Divider()
                        }
                    }
                    .padding(.horizontal)
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
        .navigationTitle("Weekly Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(verticalSizeClass == .compact ? .hidden : .automatic, for: .tabBar)
        .task {
            if viewModel.entries.isEmpty { await viewModel.loadAll() }
            if offPlanDays.isEmpty {
                let calendar = Calendar.current
                let checkins = (try? await checkinRepository.fetchOffPlanDays()) ?? []
                offPlanDays = Set(checkins.compactMap { checkin -> Date? in
                    guard let checkinDate = DateFormatting.date(fromISODate: checkin.checkinDate),
                          let offPlanDay = calendar.date(byAdding: .day, value: -1, to: checkinDate)
                    else { return nil }
                    return calendar.startOfDay(for: offPlanDay)
                })
            }
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
            HStack {
                Text("Weight Over Time")
                    .font(.headline)
                Spacer()
                if weightPoints.contains(where: \.isOffPlanWeek) {
                    Label("Off-plan day this week", systemImage: "circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
            Chart {
                ForEach(weightPoints) { point in
                    LineMark(x: .value("Week", point.date), y: .value("Weight (kg)", point.weightKg))
                        .foregroundStyle(.blue)
                    PointMark(x: .value("Week", point.date), y: .value("Weight (kg)", point.weightKg))
                        .foregroundStyle(point.isOffPlanWeek ? .green : .blue)
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
                                if selectedWeightPoint.isOffPlanWeek {
                                    Text("Off-plan day")
                                        .font(.caption2)
                                        .foregroundStyle(.green)
                                }
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
            // with the "Off-plan day this week" legend sitting right above
            // the chart - this reserves headroom inside the chart's own
            // frame for it to render into instead.
            .chartPlotStyle { plotArea in
                plotArea.padding(.top, 32)
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
        let origin = geometry[proxy.plotFrame!].origin
        let xPosition = location.x - origin.x
        guard let date: Date = proxy.value(atX: xPosition) else { return }
        selectedWeightPoint = weightPoints.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    private var headerRow: some View {
        HStack(spacing: 16) {
            Text("Week")
                .frame(width: 84, alignment: .leading)
            ForEach(columns, id: \.title) { column in
                Text(column.title)
                    .frame(width: 84, alignment: .center)
            }
            Text("Weight")
                .frame(width: 72, alignment: .center)
        }
        .font(.caption.bold())
        .foregroundStyle(.secondary)
        .padding(.vertical, 8)
    }

    private func row(for entry: WeeklyLogEntry) -> some View {
        let goal = viewModel.goal(for: entry)
        return HStack(spacing: 16) {
            Text(weekLabel(for: entry))
                .font(.subheadline.weight(.medium))
                .frame(width: 84, alignment: .leading)

            ForEach(columns, id: \.title) { column in
                cell(goal: goal.flatMap(column.goal), avg: column.avg(entry), unit: column.unit)
                    .frame(width: 84)
            }

            weightCell(entry)
                .frame(width: 72)
        }
        .padding(.vertical, 10)
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
        if abs(ratio - 1) <= 0.05 { return .green }
        return (ratio > 1.15 || ratio < 0.85) ? .orange : .primary
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
