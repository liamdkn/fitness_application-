import SwiftUI

/// Redesigned weekly check-in: three pages - weight, then measurements +
/// photos, then an auto-generated recap of the week's actual tracked data.
/// The old page 2/3 subjective survey (mood, stress, discipline,
/// self-rated adherence, biggest win) is gone entirely - it was collected
/// every week and never once read back anywhere in the app. This keeps
/// only what's genuinely useful to look back on: hard numbers you didn't
/// have to type in twice, since they're computed from data already logged
/// through the week.
struct WeeklyCheckinFlow: View {
    var onSaved: () async -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    // Page 1
    @State private var weightText = ""
    @State private var activeGoal: UserGoal?
    @State private var weekNumber: Int?
    @State private var avgWeightThisWeek: Double?
    @State private var avgWeightLastWeek: Double?

    // Page 3
    @State private var recap: WeeklyCheckinRecap?
    @State private var isLoadingRecap = false
    @State private var nutritionRating = 3
    @State private var nutritionNotes = ""
    @State private var trainingRating = 3
    @State private var trainingNotes = ""

    @State private var savedCheckin: WeeklyCheckin?
    @State private var errorMessage: String?
    @State private var isSaving = false

    private let goalsRepository = GoalsRepository()
    private let checkinRepository = WeeklyCheckinRepository()
    private let measurementRepository = BodyMeasurementRepository()
    private let photoRepository = ProgressPhotoRepository()
    private let nutritionRepository = NutritionRepository()
    private let healthRepository = HealthRepository()
    private let workoutRepository = WorkoutRepository()
    private let bodyWeightRepository = BodyWeightRepository()
    private let cardioSessionRepository = CardioSessionRepository()

    var body: some View {
        NavigationStack {
            Form {
                switch page {
                case 0: pageOne
                case 1: pageTwo
                default: pageThree
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Weekly Check-In (\(page + 1)/3)")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                if page == 0 {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("Skip") { dismiss() }
                        Button("Next") {
                            Task { await saveCheckinAndAdvance() }
                        }
                        .disabled(isSaving)
                    }
                }
                if page == 1 {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("Next") {
                            // Set synchronously so page 3 renders its
                            // loading state on the very first frame -
                            // `loadRecap()`'s own flag flip happens inside
                            // the dispatched Task, a beat after `page = 2`
                            // already triggered a render, which otherwise
                            // showed "not enough data" for one frame before
                            // flipping to the spinner.
                            isLoadingRecap = true
                            page = 2
                            Task { await loadRecap() }
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") { page -= 1 }
                    }
                }
                if page == 2 {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("Done") {
                            Task { await saveRatingsAndFinish() }
                        }
                        .disabled(isSaving)
                    }
                }
            }
            .interactiveDismissDisabled()
            .task { await loadContext() }
        }
    }

    @ViewBuilder
    private var pageOne: some View {
        if let weekNumber, let activeGoal {
            Section {
                Text("Week \(weekNumber) of your \(activeGoal.phaseType.displayName) complete!")
                    .font(.headline)
                Text(weightSummaryText)
                    .foregroundStyle(.secondary)
            }
        }
        Section("This Week") {
            HStack {
                Text("Weight")
                Spacer()
                TextField("-", text: $weightText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text("kg").foregroundStyle(.secondary).font(.caption)
            }

            if let weekNumber, let activeGoal {
                Text("Week \(weekNumber) of \(activeGoal.durationWeeks) (\(activeGoal.phaseType.displayName))")
                    .foregroundStyle(.secondary)
            } else {
                Text("No active phase - set one up in Settings.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// "Your average weight this week was 80.9 kg, 0.4 kg down from last
    /// week's average." - both averages are the same rolling-7-days
    /// windows `loadContext()` computes, not a single weigh-in, so a
    /// noisy single reading doesn't read as the week's real trend. Falls
    /// back to just this week's number (or a "not enough weigh-ins yet"
    /// line) when there isn't a full prior week to compare against.
    private var weightSummaryText: String {
        guard let avgWeightThisWeek else {
            return "Not enough weigh-ins yet this week to show an average."
        }
        let thisWeekText = String(format: "%.1f kg", avgWeightThisWeek)
        guard let avgWeightLastWeek else {
            return "Your average weight this week was \(thisWeekText)."
        }
        let delta = avgWeightThisWeek - avgWeightLastWeek
        let deltaText = String(format: "%.1f kg", abs(delta))
        if abs(delta) < 0.05 {
            return "Your average weight this week was \(thisWeekText), unchanged from last week's average."
        }
        let direction = delta < 0 ? "down" : "up"
        return "Your average weight this week was \(thisWeekText), which is \(deltaText) \(direction) from last week's average."
    }

    @ViewBuilder
    private var pageTwo: some View {
        if let savedCheckin {
            Section {
                MeasurementsPhotosCaptureView(
                    onSaveMeasurement: { waist, left, right in
                        try await measurementRepository.log(
                            waistCm: waist,
                            leftBicepCm: left,
                            rightBicepCm: right,
                            goalId: activeGoal?.id,
                            weeklyCheckinId: savedCheckin.id,
                            source: "weekly_checkin"
                        )
                    },
                    onSavePhoto: { data in
                        try await photoRepository.upload(
                            imageData: data,
                            takenAt: Date(),
                            goalId: activeGoal?.id,
                            weeklyCheckinId: savedCheckin.id
                        )
                    }
                )
            }
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private var pageThree: some View {
        if isLoadingRecap {
            Section {
                HStack {
                    Spacer()
                    ProgressView("Crunching this week's numbers...")
                    Spacer()
                }
            }
        } else if let recap {
            Section("Nutrition") {
                recapRow(label: "Avg calories", actual: recap.avgCalories.map { Int($0) }, target: recap.calorieTarget.map { Int($0) }, unit: "kcal")
                recapRow(label: "Avg protein", actual: recap.avgProteinG.map { Int($0) }, target: recap.proteinTarget.map { Int($0) }, unit: "g")
                ratingPicker(label: "Rate this week's nutrition", selection: $nutritionRating)
                TextField("What could we do better next week?", text: $nutritionNotes, axis: .vertical)
                    .lineLimit(2...4)
            }
            Section("Activity") {
                recapRow(label: "Avg steps", actual: recap.avgSteps, target: recap.stepTarget, unit: nil)
                recapCountRow(label: "Training sessions", completed: recap.sessionsCompleted, target: recap.sessionsTarget)
                if recap.cardioSessionsTarget != nil {
                    recapCountRow(label: "Cardio sessions", completed: recap.cardioSessionsCompleted, target: recap.cardioSessionsTarget)
                }
                ratingPicker(label: "Rate this week's training sessions", selection: $trainingRating)
                TextField("What could we do better next week?", text: $trainingNotes, axis: .vertical)
                    .lineLimit(2...4)
            }
            Section("Weight") {
                HStack {
                    Text("Change this week")
                    Spacer()
                    if let change = recap.weightChangeKg {
                        Text(String(format: "%+.1f kg", change))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Not enough weigh-ins").foregroundStyle(.secondary)
                    }
                }
                if let target = recap.weeklyWeightChangeTargetKg {
                    HStack {
                        Text("Target pace")
                        Spacer()
                        Text(String(format: "%+.2f kg/week", target)).foregroundStyle(.secondary)
                    }
                }
            }
            if recap.daysLogged < 4 {
                Section {
                    Text("Only \(recap.daysLogged) day\(recap.daysLogged == 1 ? "" : "s") logged this week - these averages are thin.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        } else {
            Section {
                Text("Not enough logged data this week to build a recap.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func recapRow(label: String, actual: Int?, target: Int?, unit: String?) -> some View {
        HStack {
            Text(label)
            Spacer()
            if let actual {
                Text(unit.map { "\(actual) \($0)" } ?? "\(actual)")
            } else {
                Text("\u{2014}").foregroundStyle(.secondary)
            }
            if let target {
                Text("/ \(target)\(unit.map { " \($0)" } ?? "") target")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Same 1-5 segmented picker `DailyCheckinSheet.ratingPicker` uses for
    /// Energy/Soreness - matching that existing convention rather than
    /// introducing a different rating control for these two.
    @ViewBuilder
    private func ratingPicker(label: String, selection: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.subheadline)
            Picker(label, selection: selection) {
                ForEach(1...5, id: \.self) { value in
                    Text("\(value)").tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    @ViewBuilder
    private func recapCountRow(label: String, completed: Int, target: Int?) -> some View {
        HStack {
            Text(label)
            Spacer()
            if let target {
                Text("\(completed) / \(target)")
            } else {
                Text("\(completed)")
            }
        }
    }

    private func loadContext() async {
        do {
            activeGoal = try await goalsRepository.fetchCurrentGoal()
            if let activeGoal {
                // `phaseStartedAt`, not `effectiveFrom` - a mid-phase
                // nutrition-target adjustment inserts a new row with a
                // later `effectiveFrom`, and week-counting shouldn't reset
                // just because the numbers changed partway through.
                let phaseStartedAtDate = ISO8601DateFormatter().date(from: activeGoal.phaseStartedAt + "T00:00:00Z") ?? Date()
                let days = Calendar.current.dateComponents([.day], from: phaseStartedAtDate, to: Date()).day ?? 0
                weekNumber = max(1, days / 7 + 1)
            }
            if let mostRecent = try await checkinRepository.fetchMostRecent(), let weight = mostRecent.weightKg {
                weightText = String(format: "%.1f", weight)
            }

            // Same rolling-7-days convention `loadRecap()` uses below, just
            // two windows back to back - this week's and the one before it.
            let calendar = Calendar.current
            let end = calendar.startOfDay(for: Date())
            let thisWeekStart = calendar.date(byAdding: .day, value: -6, to: end) ?? end
            let lastWeekEnd = calendar.date(byAdding: .day, value: -1, to: thisWeekStart) ?? thisWeekStart
            let lastWeekStart = calendar.date(byAdding: .day, value: -6, to: lastWeekEnd) ?? lastWeekEnd

            async let thisWeekWeightsResult = try? bodyWeightRepository.fetchRange(from: thisWeekStart, to: end)
            async let lastWeekWeightsResult = try? bodyWeightRepository.fetchRange(from: lastWeekStart, to: lastWeekEnd)
            let thisWeekWeights = await thisWeekWeightsResult ?? []
            let lastWeekWeights = await lastWeekWeightsResult ?? []
            avgWeightThisWeek = average(thisWeekWeights.map(\.weightKg))
            avgWeightLastWeek = average(lastWeekWeights.map(\.weightKg))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Saves the recap page's ratings/notes onto the row `save()` already
    /// created when page 1 advanced, then marks the check-in complete -
    /// mirrors `saveCheckinAndAdvance()`'s own error handling rather than
    /// silently swallowing a failed save.
    private func saveRatingsAndFinish() async {
        isSaving = true
        defer { isSaving = false }

        if let savedCheckin {
            do {
                try await checkinRepository.updateRatings(
                    id: savedCheckin.id,
                    nutritionRating: nutritionRating,
                    nutritionNotes: nutritionNotes.isEmpty ? nil : nutritionNotes,
                    trainingRating: trainingRating,
                    trainingNotes: trainingNotes.isEmpty ? nil : trainingNotes
                )
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        CheckinAvailabilityService.shared.checkinCompleted(.weekly)
        dismiss()
    }

    private func saveCheckinAndAdvance() async {
        isSaving = true
        defer { isSaving = false }

        do {
            let checkin = try await checkinRepository.save(
                date: Date(),
                goalId: activeGoal?.id,
                weekNumber: weekNumber,
                overallRating7d: nil,
                weightKg: Double(weightText),
                energyLevel: nil,
                sorenessLevel: nil,
                stressLevel: nil,
                stressReason: nil,
                biggestWin: nil,
                moodNotes: nil,
                overallAdherence: nil,
                trainingAdherence: nil,
                nutritionAdherence: nil,
                disciplineLevel: nil,
                upcomingDistractions: nil
            )
            savedCheckin = checkin
            errorMessage = nil
            page = 1
            CheckinAvailabilityService.shared.checkinCompleted(.weekly)
            await onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Rolling 7 days ending today (not a Monday-Sunday calendar week, on
    /// purpose - a check-in recaps "the week you just lived," whichever
    /// weekday you happen to check in on, mirroring how page one already
    /// talks about "the previous 7 days").
    private func loadRecap() async {
        isLoadingRecap = true
        defer { isLoadingRecap = false }

        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -6, to: end) ?? end

        async let nutritionResult = try? nutritionRepository.fetchRange(from: start, to: end)
        async let stepLogsResult = try? healthRepository.fetchStepLogs(from: start, to: end)
        async let workoutsResult = try? workoutRepository.fetchWorkouts(from: start, to: end)
        async let cardioResult = try? cardioSessionRepository.fetchHistory(from: start, to: end)
        async let weightsResult = try? bodyWeightRepository.fetchRange(from: start, to: end)

        let nutritionLogs = await nutritionResult ?? []
        let stepLogs = await stepLogsResult ?? []
        let workouts = await workoutsResult ?? []
        let cardioHistory = await cardioResult ?? []
        let weights = await weightsResult ?? []

        guard !(nutritionLogs.isEmpty && stepLogs.isEmpty && workouts.isEmpty && weights.isEmpty) else {
            recap = nil
            return
        }

        let avgSteps: Int? = stepLogs.isEmpty ? nil : stepLogs.map(\.stepCount).reduce(0, +) / stepLogs.count
        let weightChange: Double? = {
            guard let first = weights.first, let last = weights.last, first.id != last.id else { return nil }
            return last.weightKg - first.weightKg
        }()

        recap = WeeklyCheckinRecap(
            avgCalories: average(nutritionLogs.map(\.calories)),
            calorieTarget: activeGoal?.dailyCalorieTarget,
            avgProteinG: average(nutritionLogs.map(\.proteinG)),
            proteinTarget: activeGoal?.proteinGTarget,
            avgSteps: avgSteps,
            stepTarget: activeGoal?.stepTarget,
            sessionsCompleted: workouts.filter { $0.endedAt != nil }.count,
            sessionsTarget: activeGoal?.strengthSessionsPerWeek,
            cardioSessionsCompleted: cardioHistory.filter { $0.endedAt != nil }.count,
            cardioSessionsTarget: activeGoal?.cardioSessionsPerWeek,
            weightChangeKg: weightChange,
            weeklyWeightChangeTargetKg: activeGoal?.weeklyWeightChangeKg,
            daysLogged: nutritionLogs.count
        )
    }

    private func average(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}

private struct WeeklyCheckinRecap {
    let avgCalories: Double?
    let calorieTarget: Double?
    let avgProteinG: Double?
    let proteinTarget: Double?
    let avgSteps: Int?
    let stepTarget: Int?
    let sessionsCompleted: Int
    let sessionsTarget: Int?
    let cardioSessionsCompleted: Int
    let cardioSessionsTarget: Int?
    let weightChangeKg: Double?
    let weeklyWeightChangeTargetKg: Double?
    let daysLogged: Int
}
