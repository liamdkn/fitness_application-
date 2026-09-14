import SwiftUI

/// The "trainer's spreadsheet" - a scannable, week-by-week table of
/// averages for judging progress across time. Distinct from Weekly
/// Insights (which answers "how is *this* week going," forward-looking and
/// actionable) - this answers "how did each week compare to the last,"
/// backward-looking and plain, on purpose: no scoring or analysis here,
/// just the numbers. Tapping a row is the bridge into Weekly Insights for
/// that specific week, where the "why" lives.
struct WeeklyLogView: View {
    @StateObject private var viewModel = WeeklyLogViewModel()

    var body: some View {
        List {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            } else if viewModel.entries.isEmpty && !viewModel.isLoading {
                Text("No weeks logged yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(viewModel.entries.enumerated()), id: \.element.id) { index, entry in
                    NavigationLink {
                        WeeklyInsightsView(initialWeekStart: entry.weekStartDate)
                    } label: {
                        WeeklyLogRow(entry: entry, previousWeekWeightKg: viewModel.entries[safe: index + 1]?.avgWeightKg)
                    }
                    .task {
                        await viewModel.loadMoreIfNeeded(currentEntry: entry)
                    }
                }
                if viewModel.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Weekly Log")
        .task { await viewModel.loadInitial() }
        .refreshable { await viewModel.loadInitial() }
    }
}

private struct WeeklyLogRow: View {
    let entry: WeeklyLogEntry
    let previousWeekWeightKg: Double?

    private var weekRangeLabel: String {
        let calendar = Calendar.current
        let start = entry.weekStartDate
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
    }

    private var weightLine: String? {
        guard let avgWeightKg = entry.avgWeightKg else { return nil }
        var line = String(format: "%.1f kg", avgWeightKg)
        if let previousWeekWeightKg {
            let delta = avgWeightKg - previousWeekWeightKg
            line += String(format: " (%+.1f)", delta)
        }
        return line
    }

    private var nutritionLine: String? {
        guard entry.avgCalories != nil || entry.avgProteinG != nil || entry.avgCarbsG != nil || entry.avgFatG != nil else {
            return nil
        }
        var parts: [String] = []
        if let avgCalories = entry.avgCalories {
            parts.append("\(Int(avgCalories.rounded())) kcal")
        }
        var macros: [String] = []
        if let avgProteinG = entry.avgProteinG { macros.append("\(Int(avgProteinG.rounded()))g P") }
        if let avgCarbsG = entry.avgCarbsG { macros.append("\(Int(avgCarbsG.rounded()))g C") }
        if let avgFatG = entry.avgFatG { macros.append("\(Int(avgFatG.rounded()))g F") }
        if !macros.isEmpty { parts.append(macros.joined(separator: " / ")) }
        return parts.joined(separator: " · ")
    }

    private var stepsLine: String? {
        guard let avgSteps = entry.avgSteps else { return nil }
        return "\(Int(avgSteps.rounded())) steps/day"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(weekRangeLabel)
                    .font(.subheadline.bold())
                    .foregroundStyle(.primary)
                Spacer()
                if let weightLine {
                    Text(weightLine)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                }
            }

            if let nutritionLine {
                Text(nutritionLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let stepsLine {
                Text(stepsLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
