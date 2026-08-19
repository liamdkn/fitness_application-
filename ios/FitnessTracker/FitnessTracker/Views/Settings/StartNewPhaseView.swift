import SwiftUI

struct StartNewPhaseView: View {
    let onCreated: (UserGoal) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var phaseType: GoalPhaseType = .cut
    @State private var startDate = Date()
    @State private var startingWeightKg = ""
    @State private var durationWeeks = "12"
    @State private var dailyCalorieTarget = ""
    @State private var proteinGTarget = ""
    @State private var fatGTarget = ""
    @State private var weeklyRateKg = ""
    @State private var stepTarget = ""
    @State private var sleepTargetHours = ""
    @State private var cardioSessionsPerWeek = ""
    @State private var cardioMinutesPerSession = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var createdGoal: UserGoal?
    private let repository = GoalsRepository()
    private let measurementRepository = BodyMeasurementRepository()
    private let photoRepository = ProgressPhotoRepository()

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
                if let createdGoal {
                    Section {
                        Text("\(createdGoal.phaseType.displayName) phase started.")
                            .font(.headline)
                        Text("Add your starting measurements and photos below (optional, but useful to compare against later).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Section {
                        MeasurementsPhotosCaptureView(
                            onSaveMeasurement: { waist, left, right in
                                try? await measurementRepository.log(
                                    waistCm: waist,
                                    leftBicepCm: left,
                                    rightBicepCm: right,
                                    goalId: createdGoal.id,
                                    source: "phase_start"
                                )
                            },
                            onSavePhoto: { data in
                                try? await photoRepository.upload(imageData: data, takenAt: Date(), goalId: createdGoal.id)
                            }
                        )
                    }
                    Section {
                        Button("Done") { dismiss() }
                    }
                } else {
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
                                Text("Start Phase")
                            }
                        }
                        .disabled(!isValid || isSaving)
                    }
                }
            }
            .navigationTitle("New Phase")
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
            let goal = try await repository.saveGoal(
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
            createdGoal = goal
            onCreated(goal)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct LabeledField: View {
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
            Text(unit).foregroundStyle(.secondary).font(.caption)
        }
    }
}
