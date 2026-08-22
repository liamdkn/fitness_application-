import Charts
import SwiftUI
import UIKit

private enum NutritionField: Hashable {
    case calories, protein, carbs, fat
}

private enum NutritionTrendMetric: String, CaseIterable, Identifiable {
    case calories = "Calories"
    case protein = "Protein"
    var id: String { rawValue }
}

struct NutritionEntryView: View {
    @State private var selectedDate = Date()
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var recentLogs: [NutritionLog] = []
    @State private var currentLogSource: String?
    @State private var goal: UserGoal?
    @State private var trendMetric: NutritionTrendMetric = .calories
    @State private var showingManualEntry = false
    @State private var errorMessage: String?
    private let repository = NutritionRepository()
    private let goalsRepository = GoalsRepository()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        DatePicker(
                            "",
                            selection: $selectedDate,
                            in: ...Date(),
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .onChange(of: selectedDate) { _, _ in Task { await loadForSelectedDate() } }
                        Spacer()
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

                    if trendPoints.count < 2 {
                        Text("Log a few more days to see a trend.")
                            .foregroundStyle(.secondary)
                    } else {
                        Chart {
                            ForEach(trendPoints) { point in
                                BarMark(
                                    x: .value("Date", point.date, unit: .day),
                                    y: .value(trendMetric.rawValue, trendMetric == .calories ? point.calories : point.protein)
                                )
                                .foregroundStyle(trendMetric == .calories ? Color.orange : Color.blue)
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

                    if let weeklyAverage {
                        Divider()
                        HStack {
                            Text("Avg calories")
                            Spacer()
                            Text("\(Int(weeklyAverage.calories)) kcal")
                                .foregroundStyle(.secondary)
                        }
                        if let target = goal?.dailyCalorieTarget {
                            Text(deltaText(avg: weeklyAverage.calories, target: target, unit: "kcal"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Avg protein")
                            Spacer()
                            Text("\(Int(weeklyAverage.protein))g")
                                .foregroundStyle(.secondary)
                        }
                        if let target = goal?.proteinGTarget {
                            Text(deltaText(avg: weeklyAverage.protein, target: target, unit: "g"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("Based on your last \(weeklyAverage.days) logged day\(weeklyAverage.days == 1 ? "" : "s").")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
                }
            }
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

    private struct TrendPoint: Identifiable {
        let id = UUID()
        let date: Date
        let calories: Double
        let protein: Double
    }

    private var trendPoints: [TrendPoint] {
        recentLogs.compactMap { log in
            guard let date = DateFormatting.date(fromISODate: log.date) else { return nil }
            return TrendPoint(date: date, calories: log.calories, protein: log.proteinG)
        }.sorted { $0.date < $1.date }
    }

    private var targetLine: Double? {
        guard let goal else { return nil }
        return trendMetric == .calories ? goal.dailyCalorieTarget : goal.proteinGTarget
    }

    /// Averages the most recently *logged* days (not a strict calendar
    /// week) - `recentLogs` is already ordered most-recent-first, so this
    /// is simply its first 7 entries.
    private var weeklyAverage: (calories: Double, protein: Double, days: Int)? {
        let sample = Array(recentLogs.prefix(7))
        guard !sample.isEmpty else { return nil }
        let avgCalories = sample.reduce(0.0) { $0 + $1.calories } / Double(sample.count)
        let avgProtein = sample.reduce(0.0) { $0 + $1.proteinG } / Double(sample.count)
        return (avgCalories, avgProtein, sample.count)
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

    private func loadGoal() async {
        goal = try? await goalsRepository.fetchCurrentGoal()
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

    /// Apple Watch-inspired: rings sit edge-to-edge (no gaps), each a solid
    /// color with a dark, muted track showing the unfilled remainder (the
    /// same way a real Activity ring shows its "remaining" portion as a
    /// dim version of the ring's own hue, not a pale one). A single round
    /// stroke cap naturally rounds off both the start (12 o'clock) and the
    /// leading edge of the current fill - no separate overlaid shape - so
    /// there's exactly one consistent semicircular cap style at each end.
    @ViewBuilder
    private func ringBand(for ring: MacroRing, diameter: CGFloat) -> some View {
        let baseProgress = min(ring.progress, 1.0)

        ZStack {
            Circle()
                .stroke(ring.color.darkened(by: 0.6), lineWidth: ringWidth)
            Circle()
                .trim(from: 0, to: baseProgress)
                .stroke(ring.color, style: StrokeStyle(lineWidth: ringWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeInOut(duration: 0.3), value: ring.progress)
    }
}

private extension Color {
    /// Blends toward white by a fixed ratio and returns a fully opaque
    /// result - unlike `.opacity()`, this looks identical regardless of
    /// what's rendered behind it (a light-mode white background vs a
    /// dark-mode near-black one), since there's no transparency for the
    /// backdrop to show through.
    func lightened(by amount: Double) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return Color(
            red: r + (1 - r) * amount,
            green: g + (1 - g) * amount,
            blue: b + (1 - b) * amount
        )
    }

    /// Blends toward black by a fixed ratio - the darker end of the
    /// angular gradient used for each ring's glossy fill.
    func darkened(by amount: Double) -> Color {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        return Color(
            red: r * (1 - amount),
            green: g * (1 - amount),
            blue: b * (1 - amount)
        )
    }
}

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
