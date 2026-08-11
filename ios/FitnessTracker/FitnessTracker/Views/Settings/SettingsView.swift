import SwiftUI

struct SettingsView: View {
    @State private var dailyCalorieTarget = ""
    @State private var proteinGTarget = ""
    @State private var carbsGTarget = ""
    @State private var fatGTarget = ""
    @State private var targetWeightKg = ""
    @State private var weeklyWeightChangeKg = ""
    @State private var stepTarget = ""
    @State private var sleepTargetHours = ""
    @State private var currentGoal: UserGoal?
    @State private var errorMessage: String?
    @State private var isSaving = false
    @ObservedObject private var healthSync = HealthSyncService.shared
    private let repository = GoalsRepository()

    private var isValid: Bool {
        Double(dailyCalorieTarget) != nil && Double(proteinGTarget) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Cut Goals") {
                    if let currentGoal {
                        Text("In effect since \(currentGoal.effectiveFrom)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No goal set yet - add one below.")
                            .foregroundStyle(.secondary)
                    }

                    LabeledField(label: "Daily Calories", text: $dailyCalorieTarget, unit: "kcal")
                    LabeledField(label: "Protein Target", text: $proteinGTarget, unit: "g")
                    LabeledField(label: "Carbs Target", text: $carbsGTarget, unit: "g")
                    LabeledField(label: "Fat Target", text: $fatGTarget, unit: "g")
                    LabeledField(label: "Target Weight", text: $targetWeightKg, unit: "kg")
                    LabeledField(label: "Weekly Change", text: $weeklyWeightChangeKg, unit: "kg")
                    LabeledField(label: "Step Target", text: $stepTarget, unit: "steps")
                    LabeledField(label: "Sleep Target", text: $sleepTargetHours, unit: "hrs")

                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }

                    Button {
                        Task { await saveGoal() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save Goal")
                        }
                    }
                    .disabled(!isValid || isSaving)
                }

                Section("Apple Health") {
                    healthStatusRow
                    Button("Sync Now") {
                        Task { await healthSync.requestAuthorizationAndSync() }
                    }
                }

                Section("Account") {
                    Button("Sign Out", role: .destructive) {
                        Task { try? await SupabaseService.shared.signOut() }
                    }
                }
            }
            .navigationTitle("Settings")
            .task { await loadGoal() }
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

    private func loadGoal() async {
        do {
            guard let goal = try await repository.fetchCurrentGoal() else { return }
            currentGoal = goal
            dailyCalorieTarget = String(goal.dailyCalorieTarget)
            proteinGTarget = String(goal.proteinGTarget)
            carbsGTarget = goal.carbsGTarget.map { String($0) } ?? ""
            fatGTarget = goal.fatGTarget.map { String($0) } ?? ""
            targetWeightKg = goal.targetWeightKg.map { String($0) } ?? ""
            weeklyWeightChangeKg = goal.weeklyWeightChangeKg.map { String($0) } ?? ""
            stepTarget = goal.stepTarget.map { String($0) } ?? ""
            sleepTargetHours = goal.sleepTargetMinutes.map { String($0 / 60) } ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveGoal() async {
        guard
            let calories = Double(dailyCalorieTarget),
            let protein = Double(proteinGTarget)
        else { return }

        isSaving = true
        defer { isSaving = false }

        do {
            currentGoal = try await repository.saveGoal(
                dailyCalorieTarget: calories,
                proteinGTarget: protein,
                carbsGTarget: Double(carbsGTarget),
                fatGTarget: Double(fatGTarget),
                targetWeightKg: Double(targetWeightKg),
                weeklyWeightChangeKg: Double(weeklyWeightChangeKg),
                stepTarget: Int(stepTarget),
                sleepTargetMinutes: Int(sleepTargetHours).map { $0 * 60 }
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct LabeledField: View {
    let label: String
    @Binding var text: String
    let unit: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("-", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(unit)
                .foregroundStyle(.secondary)
                .font(.caption)
        }
    }
}
