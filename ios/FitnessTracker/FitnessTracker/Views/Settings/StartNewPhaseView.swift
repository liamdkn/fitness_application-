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
    @State private var strengthSessionsPerWeek = ""
    @State private var strengthOptionalSessions = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var createdGoal: UserGoal?
    private let repository = GoalsRepository()
    private let measurementRepository = BodyMeasurementRepository()
    private let photoRepository = ProgressPhotoRepository()
    private let routineRepository = RoutineRepository()

    /// A start date after today queues the phase rather than starting it
    /// immediately - it stays dormant (excluded by `current_user_goal`'s
    /// own `effective_from <= as_of` filter) until that date arrives, at
    /// which point it naturally becomes the active phase on its own.
    private var isQueued: Bool {
        let calendar = Calendar.current
        return calendar.startOfDay(for: startDate) > calendar.startOfDay(for: Date())
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
                if let createdGoal {
                    if isQueued {
                        Section {
                            Text("\(createdGoal.phaseType.displayName) phase queued for \(createdGoal.phaseStartedAt).")
                                .font(.headline)
                            Text("It'll become your active phase on that date - nothing about today changes until then. Come back and add starting measurements/photos once it begins.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
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

                    Section("Training Targets") {
                        LabeledField(label: "Sessions / Week", text: $strengthSessionsPerWeek, unit: "sessions")
                        LabeledField(label: "Optional Sessions", text: $strengthOptionalSessions, unit: "of those")
                        Text("Sets up (or grows) your split to match - e.g. 5 sessions with 1 optional creates Day 1-5, with Day 5 marked optional.")
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
                                Text(isQueued ? "Queue Phase" : "Start Phase")
                            }
                        }
                        .disabled(!isValid || isSaving)
                    }
                }
            }
            .navigationTitle(isQueued ? "Queue Phase" : "New Phase")
            .scrollDismissesKeyboard(.interactively)
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
                phaseStartedAt: startDate,
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
                cardioMinutesPerSession: Int(cardioMinutesPerSession),
                strengthSessionsPerWeek: Int(strengthSessionsPerWeek),
                strengthOptionalSessions: Int(strengthOptionalSessions)
            )
            createdGoal = goal
            onCreated(goal)
            errorMessage = nil
            // Only for a phase starting today - a queued future phase
            // shouldn't change what today's split looks like before it's
            // even active.
            if !isQueued {
                await growSplitToTarget(goal)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Grows (never shrinks) the active split to match the phase's
    /// strength-sessions target, so the split the user builds out always
    /// has a day for every planned session rather than drifting apart from
    /// what the phase says the week should look like. Best-effort - a
    /// failure here shouldn't block the phase itself from being created.
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
