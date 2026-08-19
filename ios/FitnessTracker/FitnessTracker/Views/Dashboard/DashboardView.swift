import Charts
import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @State private var activeSheet: DashboardSheet?
    @ObservedObject private var checkinAvailability = CheckinAvailabilityService.shared

    private enum DashboardSheet: String, Identifiable {
        case logWeight, dailyCheckin, weeklyCheckin, cardioSteps
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    CheckInsCard(
                        dailyCompleted: checkinAvailability.dailyCompletedToday,
                        weeklyDue: checkinAvailability.weeklyDue,
                        onTapDaily: { activeSheet = .dailyCheckin },
                        onTapWeekly: { activeSheet = .weeklyCheckin }
                    )

                    DashboardCard(title: "Today") {
                        VStack(alignment: .leading, spacing: 12) {
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
                            if viewModel.cardioExclusionEnabled {
                                if viewModel.cardioStepsExcludedToday > 0 {
                                    Text("\(viewModel.cardioStepsExcludedToday) cardio steps excluded")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Button("Log Cardio Steps") { activeSheet = .cardioSteps }
                            }
                            StatRow(
                                icon: "bed.double.fill",
                                label: "Sleep last night",
                                value: viewModel.lastNightSleepMinutes.map(formattedDuration) ?? "-",
                                target: viewModel.goal?.sleepTargetMinutes.map(formattedDuration)
                            )
                        }
                    }

                    DashboardCard(title: "This Week") {
                        StatRow(
                            icon: "dumbbell.fill",
                            label: "Training volume",
                            value: viewModel.weeklyVolumeKg.map { "\(Int($0)) kg" } ?? "0 kg",
                            target: nil
                        )
                    }

                    DashboardCard(title: "Weight") {
                        VStack(alignment: .leading, spacing: 12) {
                            if viewModel.recentWeights.isEmpty {
                                Text("No weigh-ins yet.")
                                    .foregroundStyle(.secondary)
                            } else {
                                Chart(viewModel.recentWeights) { log in
                                    LineMark(
                                        x: .value("Date", log.loggedAt),
                                        y: .value("Weight (kg)", log.weightKg)
                                    )
                                    PointMark(
                                        x: .value("Date", log.loggedAt),
                                        y: .value("Weight (kg)", log.weightKg)
                                    )
                                }
                                .chartYScale(domain: weightChartDomain)
                                .frame(height: 140)
                            }
                            Button("Log Weight") { activeSheet = .logWeight }
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
                await viewModel.load()
                await checkinAvailability.refresh()
            }
            .refreshable {
                await viewModel.load()
                await checkinAvailability.refresh()
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .logWeight:
                    LogWeightSheet { kg in
                        await viewModel.logWeight(kg: kg)
                    }
                case .dailyCheckin:
                    DailyCheckinSheet {
                        await viewModel.load()
                    }
                case .weeklyCheckin:
                    WeeklyCheckinFlow {
                        await viewModel.load()
                    }
                case .cardioSteps:
                    CardioStepsSheet(
                        sessions: viewModel.todayCardioSessions,
                        onSave: { before, after in await viewModel.logCardioStepSession(before: before, after: after) },
                        onDelete: { id in await viewModel.deleteCardioStepSession(id: id) }
                    )
                }
            }
        }
    }

    private func formattedDuration(_ minutes: Int) -> String {
        "\(minutes / 60)h \(minutes % 60)m"
    }

    private var displaySteps: Int? {
        guard let todaySteps = viewModel.todaySteps else { return nil }
        guard viewModel.cardioExclusionEnabled else { return todaySteps }
        return max(todaySteps - viewModel.cardioStepsExcludedToday, 0)
    }

    private var weightChartDomain: ClosedRange<Double> {
        let weights = viewModel.recentWeights.map(\.weightKg)
        guard let min = weights.min(), let max = weights.max() else { return 0...1 }
        let padding = Swift.max((max - min) * 0.2, 1)
        return (min - padding)...(max + padding)
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
                Button(action: onTapDaily) {
                    checkinRow(label: "Daily Check-In", isDone: dailyCompleted)
                }
                .buttonStyle(.plain)

                if weeklyDue {
                    Divider()
                    Button(action: onTapWeekly) {
                        checkinRow(label: "Weekly Check-In", isDone: false)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func checkinRow(label: String, isDone: Bool) -> some View {
        HStack {
            Text(label)
            Spacer()
            if isDone {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
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

private struct LogWeightSheet: View {
    let onSave: (Double) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var weightText = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Weight (kg)", text: $weightText)
                    .keyboardType(.decimalPad)
            }
            .navigationTitle("Log Weight")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        guard let kg = Double(weightText) else { return }
                        Task {
                            await onSave(kg)
                            dismiss()
                        }
                    }
                    .disabled(Double(weightText) == nil)
                }
            }
        }
    }
}

#Preview {
    DashboardView()
}
