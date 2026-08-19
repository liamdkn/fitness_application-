import SwiftUI

struct EditPhaseView: View {
    let goal: UserGoal
    let onSaved: (UserGoal) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var phaseType: GoalPhaseType
    @State private var startDate: Date
    @State private var startingWeightKg: String
    @State private var durationWeeks: String
    @State private var dailyCalorieTarget: String
    @State private var proteinGTarget: String
    @State private var fatGTarget: String
    @State private var weeklyRateKg: String
    @State private var stepTarget: String
    @State private var sleepTargetHours: String
    @State private var cardioSessionsPerWeek: String
    @State private var cardioMinutesPerSession: String
    @State private var errorMessage: String?
    @State private var isSaving = false
    private let repository = GoalsRepository()

    init(goal: UserGoal, onSaved: @escaping (UserGoal) -> Void) {
        self.goal = goal
        self.onSaved = onSaved
        _phaseType = State(initialValue: goal.phaseType)
        _startDate = State(initialValue: ISO8601DateFormatter().date(from: goal.effectiveFrom + "T00:00:00Z") ?? Date())
        _startingWeightKg = State(initialValue: goal.startingWeightKg.map { String($0) } ?? "")
        _durationWeeks = State(initialValue: String(goal.durationWeeks))
        _dailyCalorieTarget = State(initialValue: String(goal.dailyCalorieTarget))
        _proteinGTarget = State(initialValue: String(goal.proteinGTarget))
        _fatGTarget = State(initialValue: goal.fatGTarget.map { String($0) } ?? "")
        _weeklyRateKg = State(initialValue: goal.weeklyWeightChangeKg.map { String(abs($0)) } ?? "")
        _stepTarget = State(initialValue: goal.stepTarget.map { String($0) } ?? "")
        _sleepTargetHours = State(initialValue: goal.sleepTargetMinutes.map { String($0 / 60) } ?? "")
        _cardioSessionsPerWeek = State(initialValue: goal.cardioSessionsPerWeek.map { String($0) } ?? "")
        _cardioMinutesPerSession = State(initialValue: goal.cardioMinutesPerSession.map { String($0) } ?? "")
    }

    private var isValid: Bool {
        Double(dailyCalorieTarget) != nil && Double(proteinGTarget) != nil && Int(durationWeeks) != nil
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
        switch phaseType {
        case .cut: return "Weekly Weight Loss"
        case .bulk: return "Weekly Weight Gain"
        case .maintain: return "Weekly Rate"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Phase Type") {
                    Picker("Type", selection: $phaseType) {
                        ForEach(GoalPhaseType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Details") {
                    DatePicker("Start Date", selection: $startDate, displayedComponents: .date)
                    LabeledField(label: "Starting Weight", text: $startingWeightKg, unit: "kg")
                    LabeledField(label: "Duration", text: $durationWeeks, unit: "weeks")
                    if phaseType != .maintain {
                        LabeledField(label: weeklyRateLabel, text: $weeklyRateKg, unit: "kg")
                    }
                }

                Section("Nutrition Targets") {
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

                Section("Other Targets") {
                    LabeledField(label: "Step Target", text: $stepTarget, unit: "steps")
                    LabeledField(label: "Sleep Target", text: $sleepTargetHours, unit: "hrs")
                }

                Section("Cardio Targets") {
                    LabeledField(label: "Sessions / Week", text: $cardioSessionsPerWeek, unit: "sessions")
                    LabeledField(label: "Minutes / Session", text: $cardioMinutesPerSession, unit: "min")
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
                            Text("Save Changes")
                        }
                    }
                    .disabled(!isValid || isSaving)
                }
            }
            .navigationTitle("Edit Phase")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() async {
        guard
            let calories = Double(dailyCalorieTarget),
            let protein = Double(proteinGTarget),
            let weeks = Int(durationWeeks)
        else { return }

        isSaving = true
        defer { isSaving = false }

        let rateMagnitude = Double(weeklyRateKg).map { abs($0) }
        let signedRate: Double? = switch phaseType {
        case .cut: rateMagnitude.map { -$0 }
        case .maintain: 0
        case .bulk: rateMagnitude
        }

        do {
            let updated = try await repository.updateGoal(
                goalId: goal.id,
                effectiveFrom: startDate,
                phaseType: phaseType,
                startingWeightKg: Double(startingWeightKg),
                durationWeeks: weeks,
                dailyCalorieTarget: calories,
                proteinGTarget: protein,
                carbsGTarget: derivedCarbsG,
                fatGTarget: Double(fatGTarget),
                targetWeightKg: nil,
                weeklyWeightChangeKg: signedRate,
                stepTarget: Int(stepTarget),
                sleepTargetMinutes: Int(sleepTargetHours).map { $0 * 60 },
                cardioSessionsPerWeek: Int(cardioSessionsPerWeek),
                cardioMinutesPerSession: Int(cardioMinutesPerSession)
            )
            onSaved(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
