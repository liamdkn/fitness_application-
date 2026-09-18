import SwiftUI

/// Adjusts the current phase's targets - nutrition, weekly rate, steps,
/// sleep, cardio, training - without touching history. This always inserts
/// a new `user_goals` row effective from a chosen date (today or later),
/// carrying every other field forward unchanged from the current phase,
/// including `phaseStartedAt` - this is a mid-phase adjustment, not a new
/// phase, so "week X of Y" tracking shouldn't reset. Weekly Insights and
/// the Dashboard both look up whichever row was actually in effect for a
/// given day, so anything before the chosen date keeps reading against the
/// old targets.
///
/// What's deliberately NOT here: phase type, start date, starting weight,
/// and duration are the phase's fixed identity - changing any of those
/// isn't "adjusting" this phase, it's a different phase, so that goes
/// through ending this one and starting or queuing a new one instead.
struct AdjustPhaseView: View {
    let currentGoal: UserGoal
    let onSaved: (UserGoal) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var effectiveDate = Date()
    @State private var dailyCalorieTarget: String
    @State private var proteinGTarget: String
    @State private var fatGTarget: String
    @State private var weeklyRateKg: String
    @State private var stepTarget: String
    @State private var sleepTargetHours: String
    @State private var cardioSessionsPerWeek: String
    @State private var cardioMinutesPerSession: String
    @State private var strengthSessionsPerWeek: String
    @State private var strengthOptionalSessions: String
    @State private var errorMessage: String?
    @State private var isSaving = false
    private let repository = GoalsRepository()
    private let routineRepository = RoutineRepository()

    init(currentGoal: UserGoal, onSaved: @escaping (UserGoal) -> Void) {
        self.currentGoal = currentGoal
        self.onSaved = onSaved
        _dailyCalorieTarget = State(initialValue: String(currentGoal.dailyCalorieTarget))
        _proteinGTarget = State(initialValue: String(currentGoal.proteinGTarget))
        _fatGTarget = State(initialValue: currentGoal.fatGTarget.map { String($0) } ?? "")
        _weeklyRateKg = State(initialValue: currentGoal.weeklyWeightChangeKg.map { String(abs($0)) } ?? "")
        _stepTarget = State(initialValue: currentGoal.stepTarget.map { String($0) } ?? "")
        _sleepTargetHours = State(initialValue: currentGoal.sleepTargetMinutes.map { String($0 / 60) } ?? "")
        _cardioSessionsPerWeek = State(initialValue: currentGoal.cardioSessionsPerWeek.map { String($0) } ?? "")
        _cardioMinutesPerSession = State(initialValue: currentGoal.cardioMinutesPerSession.map { String($0) } ?? "")
        _strengthSessionsPerWeek = State(initialValue: currentGoal.strengthSessionsPerWeek.map { String($0) } ?? "")
        _strengthOptionalSessions = State(initialValue: currentGoal.strengthOptionalSessions.map { String($0) } ?? "")
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

    private var weeklyRateLabel: String {
        switch currentGoal.phaseType {
        case .cut: "Weekly Weight Loss"
        case .bulk: "Weekly Weight Gain"
        case .maintain: "Weekly Rate"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Effective From", selection: $effectiveDate, in: Date()..., displayedComponents: .date)
                } footer: {
                    Text("Everything through the day before this stays exactly as it was - only days from here on are judged against the new numbers.")
                }

                Section("Nutrition") {
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

                if currentGoal.phaseType != .maintain {
                    Section("Rate") {
                        LabeledField(label: weeklyRateLabel, text: $weeklyRateKg, unit: "kg")
                    }
                }

                Section("Other Targets") {
                    LabeledField(label: "Step Target", text: $stepTarget, unit: "steps")
                    LabeledField(label: "Sleep Target", text: $sleepTargetHours, unit: "hrs")
                }

                Section("Cardio Targets") {
                    LabeledField(label: "Sessions / Week", text: $cardioSessionsPerWeek, unit: "sessions")
                    LabeledField(label: "Minutes / Session", text: $cardioMinutesPerSession, unit: "min")
                }

                Section("Training Targets") {
                    LabeledField(label: "Sessions / Week", text: $strengthSessionsPerWeek, unit: "sessions")
                    LabeledField(label: "Optional Sessions", text: $strengthOptionalSessions, unit: "of those")
                    Text("Raising this grows your split to match (never shrinks it) - e.g. going from 4 to 5 adds a Day 5.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            .navigationTitle("Adjust Phase")
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

        let rateMagnitude = Double(weeklyRateKg).map { abs($0) }
        let signedRate: Double? = switch currentGoal.phaseType {
        case .cut: rateMagnitude.map { -$0 }
        case .maintain: 0
        case .bulk: rateMagnitude
        }

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
                weeklyWeightChangeKg: signedRate,
                stepTarget: Int(stepTarget),
                sleepTargetMinutes: Int(sleepTargetHours).map { $0 * 60 },
                cardioSessionsPerWeek: Int(cardioSessionsPerWeek),
                cardioMinutesPerSession: Int(cardioMinutesPerSession),
                strengthSessionsPerWeek: Int(strengthSessionsPerWeek),
                strengthOptionalSessions: Int(strengthOptionalSessions)
            )
            await growSplitToTarget(updated)
            onSaved(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Grows (never shrinks) the active split to match the phase's
    /// strength-sessions target - see `StartNewPhaseView`'s identical
    /// helper. Best-effort - a failure here shouldn't block the adjustment.
    private func growSplitToTarget(_ goal: UserGoal) async {
        guard let target = goal.strengthSessionsPerWeek else { return }
        do {
            var activeRoutine = try await routineRepository.fetchActiveRoutine()
            if activeRoutine == nil {
                activeRoutine = try await routineRepository.createRoutine(name: "My Split")
            }
            guard let activeRoutine else { return }
            let existingDays = try await routineRepository.fetchDays(routineId: activeRoutine.id)
            try await routineRepository.fillDaysToTarget(
                routineId: activeRoutine.id,
                existingDays: existingDays,
                targetCount: target,
                optionalCount: goal.strengthOptionalSessions ?? 0
            )
        } catch {
            // Non-critical - the split can still be built manually from the Train tab.
        }
    }
}
