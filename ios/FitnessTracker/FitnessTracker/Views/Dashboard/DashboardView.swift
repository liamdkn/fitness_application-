import Charts
import SwiftUI

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @State private var exercises: [Exercise] = []
    @State private var exercisesError: String?
    @State private var showingLogWeight = false
    @ObservedObject private var healthSync = HealthSyncService.shared
    private let exerciseRepository = ExerciseRepository()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DashboardCard(title: "Apple Health") {
                        healthStatusRow
                    }

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
                                value: viewModel.todaySteps.map { "\($0)" } ?? "-",
                                target: viewModel.goal?.stepTarget.map { "\($0)" }
                            )
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
                            Button("Log Weight") { showingLogWeight = true }
                        }
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }

                    if let exercisesError {
                        Text(exercisesError).foregroundStyle(.red)
                    } else if !exercises.isEmpty {
                        DashboardCard(title: "Exercise Progress") {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(exercises) { exercise in
                                    NavigationLink(exercise.name) {
                                        ExerciseProgressionView(exercise: exercise)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Dashboard")
            .task {
                await viewModel.load()
                await loadExercises()
            }
            .refreshable { await viewModel.load() }
            .sheet(isPresented: $showingLogWeight) {
                LogWeightSheet { kg in
                    await viewModel.logWeight(kg: kg)
                }
            }
        }
    }

    @ViewBuilder
    private var healthStatusRow: some View {
        if healthSync.isSyncing {
            Label("Syncing steps & sleep...", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.secondary)
        } else if let healthError = healthSync.errorMessage {
            Label(healthError, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.red)
        } else if let lastSynced = healthSync.lastSyncedAt {
            Label("Synced \(lastSynced, style: .relative) ago", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        } else {
            Label("Not synced yet", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    private func loadExercises() async {
        do {
            exercises = try await exerciseRepository.fetchAll()
        } catch {
            exercisesError = error.localizedDescription
        }
    }

    private func formattedDuration(_ minutes: Int) -> String {
        "\(minutes / 60)h \(minutes % 60)m"
    }

    private var weightChartDomain: ClosedRange<Double> {
        let weights = viewModel.recentWeights.map(\.weightKg)
        guard let min = weights.min(), let max = weights.max() else { return 0...1 }
        let padding = Swift.max((max - min) * 0.2, 1)
        return (min - padding)...(max + padding)
    }
}

private struct DashboardCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
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
