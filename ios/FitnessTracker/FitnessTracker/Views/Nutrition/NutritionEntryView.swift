import Charts
import SwiftUI
import UIKit

private enum NutritionField: Hashable {
    case calories, protein, carbs, fat
}

/// Week/Month/All-Time average for each macro, side by side - a single
/// number (like the old "avg calories this week") can't show whether
/// you're looking at a blip or a sustained pattern, which is the whole
/// point of adding month/all-time alongside it.
private struct MacroAveragesTable: View {
    let stats: NutritionTrendStats

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
            GridRow {
                Text("")
                Text("Week").gridColumnAlignment(.trailing)
                Text("Month").gridColumnAlignment(.trailing)
                Text("All-Time").gridColumnAlignment(.trailing)
            }
            .font(.caption2.bold())
            .foregroundStyle(.secondary)

            row(label: "Calories", averages: stats.calories, unit: "kcal")
            row(label: "Protein", averages: stats.protein, unit: "g")
            row(label: "Carbs", averages: stats.carbs, unit: "g")
            row(label: "Fat", averages: stats.fat, unit: "g")
        }
    }

    @ViewBuilder
    private func row(label: String, averages: PeriodAverages, unit: String) -> some View {
        GridRow {
            Text(label).font(.caption)
            valueText(averages.week, unit: unit)
            valueText(averages.month, unit: unit)
            valueText(averages.allTime, unit: unit)
        }
    }

    @ViewBuilder
    private func valueText(_ value: Double?, unit: String) -> some View {
        if let value {
            Text(unit == "kcal" ? "\(Int(value)) kcal" : "\(Int(value))\(unit)")
                .font(.caption)
        } else {
            Text("\u{2014}")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private enum NutritionTrendMetric: String, CaseIterable, Identifiable {
    case calories = "Calories"
    case protein = "Protein"
    case carbs = "Carbs"
    case fat = "Fat"
    var id: String { rawValue }

    var unit: String {
        self == .calories ? "kcal" : "g"
    }

    var color: Color {
        switch self {
        case .calories: .orange
        case .protein: .blue
        case .carbs: .green
        case .fat: .yellow
        }
    }

    func value(for log: NutritionLog) -> Double {
        switch self {
        case .calories: log.calories
        case .protein: log.proteinG
        case .carbs: log.carbsG
        case .fat: log.fatG
        }
    }
}

/// One macro's average over three rolling windows - week and month are
/// rolling (last 7/30 days ending today), not calendar-anchored, matching
/// how "this week" is already treated elsewhere in the app (e.g. the
/// weekly check-in recap). `nil` means nothing was logged at all in that
/// window, not zero.
private struct PeriodAverages {
    let week: Double?
    let month: Double?
    let allTime: Double?
}

private struct NutritionTrendStats {
    let calories: PeriodAverages
    let protein: PeriodAverages
    let carbs: PeriodAverages
    let fat: PeriodAverages
    let caloriesTrend: TrendDirection?

    func averages(for metric: NutritionTrendMetric) -> PeriodAverages {
        switch metric {
        case .calories: calories
        case .protein: protein
        case .carbs: carbs
        case .fat: fat
        }
    }
}

/// Apple Health-style time-range switcher for the trend chart (its own
/// Activity/Steps/etc. detail screens use a W/M/6M/Y segmented control to
/// re-scope the same graph). Nutrition is logged once a day rather than
/// continuously, so there's no meaningful "D" (day) option the way Health
/// has one - W is the shortest range here.
private enum NutritionChartRange: String, CaseIterable, Identifiable {
    case week = "W"
    case month = "M"
    case sixMonth = "6M"
    case year = "Y"
    var id: String { rawValue }

    var daysBack: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .sixMonth: 183
        case .year: 365
        }
    }

    /// Health re-buckets its own longer ranges into weekly/monthly bars
    /// rather than plotting hundreds of daily ones - matching that here is
    /// what keeps 6M/Y readable instead of an illegible wall of bars.
    var bucket: Calendar.Component? {
        switch self {
        case .week, .month: nil
        case .sixMonth: .weekOfYear
        case .year: .month
        }
    }

    var barUnit: Calendar.Component {
        bucket ?? .day
    }
}

/// Week-over-week direction for calories specifically - the one macro
/// where "which way is this actually moving" matters most for judging
/// whether a cut/bulk is on track. Needs at least one logged day in both
/// the most recent 7-day window and the 7 days before that to say
/// anything at all.
private enum TrendDirection {
    case up, down, flat

    var icon: String {
        switch self {
        case .up: "arrow.up.right"
        case .down: "arrow.down.right"
        case .flat: "arrow.right"
        }
    }

    var description: String {
        switch self {
        case .up: "Calories trending up over the past week."
        case .down: "Calories trending down over the past week."
        case .flat: "Calories holding steady over the past week."
        }
    }
}

struct NutritionEntryView: View {
    @State private var selectedDate = Date()
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var recentLogs: [NutritionLog] = []
    /// A much longer history than `recentLogs` - powers the trend chart and
    /// the week/month/all-time averages, which need more than the last 14
    /// days to say anything meaningful about "all time."
    @State private var allLogs: [NutritionLog] = []
    @State private var currentLogSource: String?
    @State private var goal: UserGoal?
    @State private var trendMetric: NutritionTrendMetric = .calories
    @State private var chartRange: NutritionChartRange = .month
    @State private var showingManualEntry = false
    @State private var errorMessage: String?
    private let repository = NutritionRepository()
    private let goalsRepository = GoalsRepository()

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Button {
                            changeDay(by: -1)
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                        Spacer()
                        // Native compact DatePicker - tapping it opens the
                        // system's own popup calendar (anchored in place,
                        // not a custom sheet), and it's a single real
                        // control rather than a Button sharing this row
                        // with the chevrons, which is what was making the
                        // chevron taps land on the wrong target.
                        DatePicker(
                            "",
                            selection: $selectedDate,
                            in: ...Date(),
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .onChange(of: selectedDate) { _, _ in
                            Task {
                                await loadForSelectedDate()
                                await loadGoal()
                            }
                        }
                        Spacer()
                        Button {
                            changeDay(by: 1)
                        } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(isToday)
                    }
                    .listRowSeparator(.hidden)

                    MacroRingsView(rings: macroRings)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    ForEach(macroRings) { ring in
                        MacroLegendRow(ring: ring)
                    }

                    if currentLogSource == "healthkit" {
                        Text("Synced from Health - editing and saving will switch this day to manual.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }

                    Button("Log Manually") { showingManualEntry = true }
                }

                Section("Trend") {
                    Picker("Metric", selection: $trendMetric) {
                        ForEach(NutritionTrendMetric.allCases) { metric in
                            Text(metric.rawValue).tag(metric)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Range", selection: $chartRange) {
                        ForEach(NutritionChartRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)

                    if chartBars.count < 2 {
                        Text("Log a few more days to see a trend.")
                            .foregroundStyle(.secondary)
                    } else {
                        Chart {
                            ForEach(chartBars) { bar in
                                BarMark(
                                    x: .value("Date", bar.date, unit: chartRange.barUnit),
                                    y: .value(trendMetric.rawValue, bar.value)
                                )
                                .foregroundStyle(trendMetric.color)
                            }
                            if let targetLine {
                                RuleMark(y: .value("Target", targetLine))
                                    .foregroundStyle(.secondary)
                                    .lineStyle(StrokeStyle(dash: [4, 3]))
                            }
                        }
                        .frame(height: 160)
                        .padding(.vertical, 4)
                    }

                    if let target = targetLine, let weekAvg = trendStats?.averages(for: trendMetric).week {
                        Text(deltaText(avg: weekAvg, target: target, unit: trendMetric.unit))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let trendStats {
                        Divider()
                        MacroAveragesTable(stats: trendStats)
                            .padding(.vertical, 4)

                        if let direction = trendStats.caloriesTrend {
                            Label(direction.description, systemImage: direction.icon)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Recent") {
                    if recentLogs.isEmpty {
                        Text("No entries yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recentLogs.prefix(7)) { log in
                            NutritionLogRow(log: log)
                        }
                        NavigationLink("View All") {
                            NutritionHistoryView()
                        }
                    }
                }
            }
            .navigationTitle("Nutrition")
            .task {
                await loadForSelectedDate()
                await loadRecent()
                await loadAllLogs()
                await loadGoal()
            }
            .sheet(isPresented: $showingManualEntry) {
                ManualNutritionEntrySheet(
                    date: selectedDate,
                    initialCalories: calories,
                    initialProtein: protein,
                    initialCarbs: carbs,
                    initialFat: fat
                ) {
                    await loadForSelectedDate()
                    await loadRecent()
                    await loadAllLogs()
                }
            }
        }
    }

    private func changeDay(by offset: Int) {
        guard let newDate = Calendar.current.date(byAdding: .day, value: offset, to: selectedDate) else { return }
        selectedDate = newDate
        Task {
            await loadForSelectedDate()
            await loadGoal()
        }
    }

    /// Rings reflect whichever date is selected - the currently loaded
    /// values for that day (from Health sync or a previous manual save),
    /// not live text-field input, since entry now happens in a sheet.
    private var macroRings: [MacroRing] {
        [
            MacroRing(label: "Calories", value: Double(calories) ?? 0, target: goal?.dailyCalorieTarget, unit: "kcal", color: .orange),
            MacroRing(label: "Protein", value: Double(protein) ?? 0, target: goal?.proteinGTarget, unit: "g", color: .blue),
            MacroRing(label: "Carbs", value: Double(carbs) ?? 0, target: goal?.carbsGTarget, unit: "g", color: .green),
            MacroRing(label: "Fat", value: Double(fat) ?? 0, target: goal?.fatGTarget, unit: "g", color: .yellow)
        ]
    }

    private struct ChartBar: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    /// Sliced from `allLogs` to whichever range is selected (W/M/6M/Y).
    /// W and M plot one bar per logged day, same as before; 6M and Y
    /// re-bucket into weekly/monthly averages instead - a year of daily
    /// bars would be unreadable, and averaging (not summing) is what makes
    /// a bucketed bar comparable to a daily one on the same y-axis.
    private var chartBars: [ChartBar] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let cutoff = calendar.date(byAdding: .day, value: -(chartRange.daysBack - 1), to: today) else { return [] }
        let logsInRange = allLogs.filter { log in
            guard let date = DateFormatting.date(fromISODate: log.date) else { return false }
            return date >= cutoff
        }

        guard let bucket = chartRange.bucket else {
            return logsInRange.compactMap { log -> ChartBar? in
                guard let date = DateFormatting.date(fromISODate: log.date) else { return nil }
                return ChartBar(date: date, value: trendMetric.value(for: log))
            }.sorted { $0.date < $1.date }
        }

        let grouped = Dictionary(grouping: logsInRange) { log -> Date in
            guard let date = DateFormatting.date(fromISODate: log.date) else { return today }
            return calendar.dateInterval(of: bucket, for: date)?.start ?? date
        }
        return grouped.map { bucketStart, logs in
            let average = logs.reduce(0.0) { $0 + trendMetric.value(for: $1) } / Double(logs.count)
            return ChartBar(date: bucketStart, value: average)
        }.sorted { $0.date < $1.date }
    }

    private var targetLine: Double? {
        guard let goal else { return nil }
        switch trendMetric {
        case .calories: return goal.dailyCalorieTarget
        case .protein: return goal.proteinGTarget
        case .carbs: return goal.carbsGTarget
        case .fat: return goal.fatGTarget
        }
    }

    private var trendStats: NutritionTrendStats? {
        guard !allLogs.isEmpty else { return nil }
        func averages(_ metric: NutritionTrendMetric) -> PeriodAverages {
            PeriodAverages(
                week: average(metric, sinceDaysAgo: 7),
                month: average(metric, sinceDaysAgo: 30),
                allTime: average(metric, sinceDaysAgo: nil)
            )
        }
        return NutritionTrendStats(
            calories: averages(.calories),
            protein: averages(.protein),
            carbs: averages(.carbs),
            fat: averages(.fat),
            caloriesTrend: caloriesTrendDirection
        )
    }

    /// `sinceDaysAgo: nil` means all time - no lower bound at all.
    private func average(_ metric: NutritionTrendMetric, sinceDaysAgo days: Int?) -> Double? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sample: [NutritionLog]
        if let days, let cutoff = calendar.date(byAdding: .day, value: -(days - 1), to: today) {
            sample = allLogs.filter { log in
                guard let date = DateFormatting.date(fromISODate: log.date) else { return false }
                return date >= cutoff
            }
        } else {
            sample = allLogs
        }
        guard !sample.isEmpty else { return nil }
        return sample.reduce(0.0) { $0 + metric.value(for: $1) } / Double(sample.count)
    }

    /// This week's average calories vs. the week before it - needs at
    /// least one logged day in both windows to say anything; a
    /// less-than-3%-or-30kcal difference reads as "holding steady" rather
    /// than flip-flopping direction on noise.
    private var caloriesTrendDirection: TrendDirection? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard
            let recentStart = calendar.date(byAdding: .day, value: -6, to: today),
            let priorStart = calendar.date(byAdding: .day, value: -13, to: today),
            let priorEnd = calendar.date(byAdding: .day, value: -7, to: today)
        else { return nil }

        func avgCalories(from start: Date, to end: Date) -> Double? {
            let sample = allLogs.filter { log in
                guard let date = DateFormatting.date(fromISODate: log.date) else { return false }
                return date >= start && date <= end
            }
            guard !sample.isEmpty else { return nil }
            return sample.reduce(0.0) { $0 + $1.calories } / Double(sample.count)
        }

        guard
            let recentAvg = avgCalories(from: recentStart, to: today),
            let priorAvg = avgCalories(from: priorStart, to: priorEnd)
        else { return nil }

        let diff = recentAvg - priorAvg
        let threshold = max(priorAvg * 0.03, 30)
        if diff > threshold { return .up }
        if diff < -threshold { return .down }
        return .flat
    }

    private func deltaText(avg: Double, target: Double, unit: String) -> String {
        let diff = avg - target
        if abs(diff) < 1 { return "Right on target." }
        let direction = diff > 0 ? "above" : "below"
        return "\(Int(abs(diff)))\(unit == "kcal" ? " kcal" : unit) \(direction) target."
    }

    private func loadForSelectedDate() async {
        do {
            if let log = try await repository.fetchLog(date: selectedDate) {
                calories = String(log.calories)
                protein = String(log.proteinG)
                carbs = String(log.carbsG)
                fat = String(log.fatG)
                currentLogSource = log.source
            } else {
                calories = ""
                protein = ""
                carbs = ""
                fat = ""
                currentLogSource = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadRecent() async {
        do {
            recentLogs = try await repository.fetchRecent(days: 14)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// A generous cap (~10 years of daily logs) rather than a literal
    /// unbounded fetch - functionally "all time" for how long anyone would
    /// realistically use this app, without an open-ended query.
    private func loadAllLogs() async {
        allLogs = (try? await repository.fetchRecent(days: 3650)) ?? []
    }

    /// Point-in-time, not "whatever's active today" - the date picker
    /// above lets you look at a past day, and its macro rings/targets
    /// should reflect whatever phase was actually active then, not
    /// today's (possibly since-adjusted) numbers.
    private func loadGoal() async {
        let allGoals = ((try? await goalsRepository.fetchPastGoals(limit: 100)) ?? [])
            .sorted { $0.effectiveFrom < $1.effectiveFrom }
        let isoDate = DateFormatting.isoDate(selectedDate)
        goal = allGoals.last { $0.effectiveFrom <= isoDate }
    }
}

/// "Today"/weekday name for the last week, then "Weekday Nth" beyond
/// that - reads more naturally in a short recent-entries list than a
/// bare date.
private func relativeDayLabel(for isoDate: String) -> String {
    guard let date = DateFormatting.date(fromISODate: isoDate) else { return isoDate }
    let calendar = Calendar.current
    let daysAgo = calendar.dateComponents(
        [.day],
        from: calendar.startOfDay(for: date),
        to: calendar.startOfDay(for: Date())
    ).day ?? 0

    if daysAgo == 0 { return "Today" }

    let weekdayFormatter = DateFormatter()
    weekdayFormatter.dateFormat = "EEEE"
    let weekday = weekdayFormatter.string(from: date)

    if daysAgo < 7 { return weekday }

    let day = calendar.component(.day, from: date)
    return "\(weekday) \(ordinal(day))"
}

private func ordinal(_ day: Int) -> String {
    let suffix: String
    switch (day % 10, day % 100) {
    case (1, let hundreds) where hundreds != 11: suffix = "st"
    case (2, let hundreds) where hundreds != 12: suffix = "nd"
    case (3, let hundreds) where hundreds != 13: suffix = "rd"
    default: suffix = "th"
    }
    return "\(day)\(suffix)"
}

struct NutritionLogRow: View {
    let log: NutritionLog

    var body: some View {
        HStack {
            Text(relativeDayLabel(for: log.date))
            Text(log.source == "healthkit" ? "Health" : "Manual")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.15), in: Capsule())
            Spacer()
            Text("\(Int(log.calories)) kcal")
                .foregroundStyle(.secondary)
        }
    }
}

private struct ManualNutritionEntrySheet: View {
    let date: Date
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var calories: String
    @State private var protein: String
    @State private var carbs: String
    @State private var fat: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: NutritionField?
    private let repository = NutritionRepository()

    init(date: Date, initialCalories: String, initialProtein: String, initialCarbs: String, initialFat: String, onSaved: @escaping () async -> Void) {
        self.date = date
        self.onSaved = onSaved
        _calories = State(initialValue: initialCalories)
        _protein = State(initialValue: initialProtein)
        _carbs = State(initialValue: initialCarbs)
        _fat = State(initialValue: initialFat)
    }

    private var isValid: Bool {
        Double(calories) != nil && Double(protein) != nil && Double(carbs) != nil && Double(fat) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledTextField(label: "Calories", text: $calories, unit: "kcal", focusedField: $focusedField, field: .calories)
                    LabeledTextField(label: "Protein", text: $protein, unit: "g", focusedField: $focusedField, field: .protein)
                    LabeledTextField(label: "Carbs", text: $carbs, unit: "g", focusedField: $focusedField, field: .carbs)
                    LabeledTextField(label: "Fat", text: $fat, unit: "g", focusedField: $focusedField, field: .fat)
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle(Text(date, style: .date))
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(!isValid || isSaving)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
        }
    }

    private func save() async {
        guard
            let caloriesValue = Double(calories),
            let proteinValue = Double(protein),
            let carbsValue = Double(carbs),
            let fatValue = Double(fat)
        else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            try await repository.upsertLog(
                date: date,
                calories: caloriesValue,
                proteinG: proteinValue,
                carbsG: carbsValue,
                fatG: fatValue
            )
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct LabeledTextField: View {
    let label: String
    @Binding var text: String
    let unit: String
    var focusedField: FocusState<NutritionField?>.Binding
    let field: NutritionField

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .focused(focusedField, equals: field)
            Text(unit)
                .foregroundStyle(.secondary)
        }
    }
}

private struct MacroRing: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let target: Double?
    let unit: String
    let color: Color

    /// Uncapped ratio - can exceed 1.0 when over target. `MacroRingsView`
    /// splits this into a base lap and an overflow lap for rendering.
    var progress: Double {
        guard let target, target > 0 else { return 0 }
        return value / target
    }

    var valueText: String {
        let unitSuffix = unit == "kcal" ? " kcal" : unit
        guard let target else { return "\(Int(value))\(unitSuffix)" }
        return "\(Int(value))/\(Int(target))\(unitSuffix)"
    }
}

/// Concentric activity-ring-style progress - calories outermost, then
/// protein, carbs, fat - reflecting the selected day's values against its
/// targets. Apple Watch-inspired: going past 100% draws a second,
/// brightened lap over the ring rather than just leaving it as an
/// indistinguishable solid closed circle.
private struct MacroRingsView: View {
    let rings: [MacroRing]

    private let ringWidth: CGFloat = 16
    private let outerDiameter: CGFloat = 160

    private func diameter(for index: Int) -> CGFloat {
        outerDiameter - CGFloat(index) * ringWidth * 2
    }

    var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.element.id) { index, ring in
                ringBand(for: ring, diameter: diameter(for: index))
            }
        }
        .frame(width: outerDiameter, height: outerDiameter)
    }

    /// Apple Watch-inspired: rings sit edge-to-edge (no gaps), each band
    /// filled with a subtle angular gradient that brightens toward the
    /// leading edge for a glossy, tubular look rather than a flat stroke.
    /// Rather than drawing a second wrapped lap when over target, the ring
    /// is always just its single closed band (trimmed to at most a full
    /// loop) with one raised, glassy capsule "puck" marking the current
    /// fill position - which naturally lands back at the top seam once
    /// you're at or past 100%, the same way a closed Activity ring reads.
    @ViewBuilder
    private func ringBand(for ring: MacroRing, diameter: CGFloat) -> some View {
        let baseProgress = min(ring.progress, 1.0)
        let capAngle = Angle.degrees(-90 + 360 * baseProgress)
        let radius = diameter / 2

        ZStack {
            // Opaque, not translucent - a semi-transparent track blends
            // against whatever's behind it, so the same `opacity(0.16)`
            // that reads as a pale tint on a white background renders as a
            // near-black notch on a dark-mode background. Pre-mixing with
            // white bakes in a fixed pale color that looks the same in
            // both appearances.
            Circle()
                .stroke(ring.color.lightened(by: 0.82), lineWidth: ringWidth)

            // The gradient's start/end always spans the full circle (not
            // just the filled arc), so `trim` reveals only a slice of it -
            // a mostly-empty ring shows just the darker end near its
            // start, and the color only brightens up to true Apple-style
            // shine as the ring nears a full lap.
            Circle()
                .trim(from: 0, to: baseProgress)
                .stroke(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: ring.color.darkened(by: 0.12), location: 0),
                            .init(color: ring.color, location: 0.55),
                            .init(color: ring.color.lightened(by: 0.35), location: 1)
                        ]),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            if baseProgress > 0.015 {
                // A vertical capsule is naturally tangent to the circle at
                // the 3 o'clock point (capAngle == 0), so it only needs
                // rotating BY capAngle itself to stay tangent anywhere else
                // - not capAngle + 90, which was pointing it radially
                // (in/out) instead of along the ring's curve.
                ZStack {
                    Capsule()
                        .fill(ring.color)
                        .frame(width: ringWidth * 0.95, height: ringWidth * 1.35)
                    // A soft top-down highlight is what sells the "glassy
                    // nub" look real Activity rings have on their puck.
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.55), .white.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: ringWidth * 0.65, height: ringWidth * 0.75)
                        .offset(y: -ringWidth * 0.22)
                }
                .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1.5)
                .rotationEffect(capAngle)
                .offset(x: radius * cos(capAngle.radians), y: radius * sin(capAngle.radians))
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeInOut(duration: 0.3), value: ring.progress)
    }
}

// `lightened(by:)`/`darkened(by:)` now live in Views/Shared/Color+Blend.swift,
// shared with ScoreRingView's identical ring-gradient treatment.

private struct MacroLegendRow: View {
    let ring: MacroRing

    var body: some View {
        HStack {
            Circle()
                .fill(ring.color)
                .frame(width: 8, height: 8)
            Text(ring.label)
            Spacer()
            Text(ring.valueText)
                .foregroundStyle(.secondary)
        }
        .font(.caption)
    }
}
