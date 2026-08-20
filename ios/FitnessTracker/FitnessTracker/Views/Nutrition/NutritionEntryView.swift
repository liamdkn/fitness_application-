import Charts
import SwiftUI

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
    @State private var goal: UserGoal?
    @State private var trendMetric: NutritionTrendMetric = .calories
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var focusedField: NutritionField?
    private let repository = NutritionRepository()
    private let goalsRepository = GoalsRepository()

    private var isValid: Bool {
        Double(calories) != nil && Double(protein) != nil && Double(carbs) != nil && Double(fat) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Progress") {
                    MacroRingsView(rings: macroRings)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    ForEach(macroRings) { ring in
                        MacroLegendRow(ring: ring)
                    }
                }

                Section("Log a Day") {
                    DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                        .onChange(of: selectedDate) { _, _ in Task { await loadForSelectedDate() } }

                    LabeledTextField(label: "Calories", text: $calories, unit: "kcal", focusedField: $focusedField, field: .calories)
                    LabeledTextField(label: "Protein", text: $protein, unit: "g", focusedField: $focusedField, field: .protein)
                    LabeledTextField(label: "Carbs", text: $carbs, unit: "g", focusedField: $focusedField, field: .carbs)
                    LabeledTextField(label: "Fat", text: $fat, unit: "g", focusedField: $focusedField, field: .fat)

                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }

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

                Section("This Week") {
                    if let weeklyAverage {
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
                    } else {
                        Text("Log a few days to see your weekly average.")
                            .foregroundStyle(.secondary)
                    }
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
                }

                Section("Recent") {
                    if recentLogs.isEmpty {
                        Text("No entries yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recentLogs) { log in
                            HStack {
                                Text(relativeDayLabel(for: log.date))
                                Spacer()
                                Text("\(Int(log.calories)) kcal")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Nutrition")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedField = nil }
                }
            }
            .task {
                await loadForSelectedDate()
                await loadRecent()
                await loadGoal()
            }
        }
    }

    /// Rings reflect whichever date is selected, live from the entry
    /// fields as they're typed - not a separate fetch, so it updates
    /// immediately rather than only after Save.
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

    private func loadForSelectedDate() async {
        do {
            if let log = try await repository.fetchLog(date: selectedDate) {
                calories = String(log.calories)
                protein = String(log.proteinG)
                carbs = String(log.carbsG)
                fat = String(log.fatG)
            } else {
                calories = ""
                protein = ""
                carbs = ""
                fat = ""
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
                date: selectedDate,
                calories: caloriesValue,
                proteinG: proteinValue,
                carbsG: carbsValue,
                fatG: fatValue
            )
            errorMessage = nil
            await loadRecent()
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

    var progress: Double {
        guard let target, target > 0 else { return 0 }
        return min(value / target, 1.0)
    }

    var valueText: String {
        let unitSuffix = unit == "kcal" ? " kcal" : unit
        guard let target else { return "\(Int(value))\(unitSuffix)" }
        return "\(Int(value))/\(Int(target))\(unitSuffix)"
    }
}

/// Concentric activity-ring-style progress - calories outermost, then
/// protein, carbs, fat - reflecting the entry form's current values
/// against today's (or whichever day is selected) targets.
private struct MacroRingsView: View {
    let rings: [MacroRing]

    var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.element.id) { index, ring in
                let inset = CGFloat(index) * 18
                Circle()
                    .stroke(ring.color.opacity(0.15), lineWidth: 10)
                    .padding(inset)
                Circle()
                    .trim(from: 0, to: ring.progress)
                    .stroke(ring.color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(inset)
                    .animation(.easeInOut(duration: 0.3), value: ring.progress)
            }
        }
        .frame(width: 160, height: 160)
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
