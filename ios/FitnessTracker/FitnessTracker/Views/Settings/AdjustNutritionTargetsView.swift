import SwiftUI

/// Adjusts nutrition targets (calories/protein/fat, carbs derived) without
/// touching history - unlike `EditPhaseView` (which mutates the current
/// phase row in place, retroactively changing what every past week since
/// its start looks like it was aiming for), this always inserts a new
/// `user_goals` row effective from a chosen date (today or later),
/// carrying every other field forward unchanged from the current phase,
/// including `phaseStartedAt` - this is a mid-phase adjustment, not a new
/// phase, so "week X of Y" tracking shouldn't reset. Weekly Insights and
/// the Dashboard both look up whichever row was actually in effect for a
/// given day, so anything before the chosen date keeps reading against
/// the old target.
struct AdjustNutritionTargetsView: View {
    let currentGoal: UserGoal
    let onSaved: (UserGoal) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var effectiveDate = Date()
    @State private var dailyCalorieTarget: String
    @State private var proteinGTarget: String
    @State private var fatGTarget: String
    @State private var errorMessage: String?
    @State private var isSaving = false
    private let repository = GoalsRepository()

    init(currentGoal: UserGoal, onSaved: @escaping (UserGoal) -> Void) {
        self.currentGoal = currentGoal
        self.onSaved = onSaved
        _dailyCalorieTarget = State(initialValue: String(currentGoal.dailyCalorieTarget))
        _proteinGTarget = State(initialValue: String(currentGoal.proteinGTarget))
        _fatGTarget = State(initialValue: currentGoal.fatGTarget.map { String($0) } ?? "")
    }

    private var isValid: Bool {
        Double(dailyCalorieTarget) != nil && Double(proteinGTarget) != nil
    }

    private var derivedCarbsG: Double? {
        guard let cal = Double(dailyCalorieTarget), let p = Double(proteinGTarget), let f = Double(fatGTarget) else { return nil }
        return max(0, (cal - p * 4 - f * 9) / 4)
    }

    private var proteinFatExceedsCalories: Bool {
        guard let cal = Double(dailyCalorieTarget), let p = Double(proteinGTarget), let f = Double(fatGTarget) else { return false }
        return p * 4 + f * 9 > cal
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Effective From", selection: $effectiveDate, in: Date()..., displayedComponents: .date)
                } footer: {
                    Text("Everything through the day before this stays exactly as it was - only days from here on are judged against the new numbers.")
                }

                Section("New Targets") {
                    LabeledField(label: "Daily Calories", text: $dailyCalorieTarget, unit: "kcal")
                    LabeledField(label: "Protein", text: $proteinGTarget, unit: "g")
                    LabeledField(label: "Fat", text: $fatGTarget, unit: "g")
                    HStack {
                        Text("Carbs")
                        Spacer()
                        Text(derivedCarbsG.map { String(format: "%.0f g", $0) } ?? "-")
                            .foregroundStyle(.secondary)
                    }
                    if proteinFatExceedsCalories {
                        Text("Protein + fat already exceed calorie target.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }

                Section {
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
            }
            .navigationTitle("Adjust Nutrition Targets")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() async {
        guard let calories = Double(dailyCalorieTarget), let protein = Double(proteinGTarget) else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let phaseStartedAt = DateFormatting.date(fromISODate: currentGoal.phaseStartedAt) ?? effectiveDate
            let updated = try await repository.saveGoal(
                effectiveFrom: effectiveDate,
                phaseStartedAt: phaseStartedAt,
                phaseType: currentGoal.phaseType,
                startingWeightKg: currentGoal.startingWeightKg,
                durationWeeks: currentGoal.durationWeeks,
                dailyCalorieTarget: calories,
                proteinGTarget: protein,
                carbsGTarget: derivedCarbsG,
                fatGTarget: Double(fatGTarget),
                targetWeightKg: currentGoal.targetWeightKg,
                weeklyWeightChangeKg: currentGoal.weeklyWeightChangeKg,
                stepTarget: currentGoal.stepTarget,
                sleepTargetMinutes: currentGoal.sleepTargetMinutes,
                cardioSessionsPerWeek: currentGoal.cardioSessionsPerWeek,
                cardioMinutesPerSession: currentGoal.cardioMinutesPerSession,
                strengthSessionsPerWeek: currentGoal.strengthSessionsPerWeek,
                strengthOptionalSessions: currentGoal.strengthOptionalSessions
            )
            onSaved(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
