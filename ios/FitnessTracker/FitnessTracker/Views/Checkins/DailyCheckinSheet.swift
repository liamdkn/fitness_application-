import Supabase
import SwiftUI

struct DailyCheckinSheet: View {
    var onSaved: () async -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var weightText = ""
    @State private var routineDays: [RoutineDay] = []
    @State private var selectedWorkoutChoice: WorkoutChoice = .rest
    @State private var energyLevel = 5
    @State private var sorenessLevel = 1
    /// Not asked any more - water is logged through the day in Liquids - but a
    /// value saved by an older check-in is carried through unchanged when this
    /// one is re-saved, rather than being wiped.
    @State private var existingYesterdayWaterMl: Int?
    @State private var yesterdayOffPlan = false
    @State private var yesterdayOffPlanNotes = ""
    @State private var yesterdayHungerLevel: Int?
    @State private var yesterdaySleepHoursText = ""
    @State private var existingSleepLog: SleepLogRecord?
    @State private var errorMessage: String?
    @State private var isSaving = false

    private let routineRepository = RoutineRepository()
    private let checkinRepository = DailyCheckinRepository()
    private let bodyWeightRepository = BodyWeightRepository()
    private let healthRepository = HealthRepository()

    private var yesterday: Date {
        Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    }

    private enum WorkoutChoice: Hashable {
        case day(UUID)
        case rest
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Today") {
                    HStack {
                        Text("Weight")
                        Spacer()
                        TextField("-", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .onChange(of: weightText) { _, newValue in
                                weightText = Self.filteredDecimalText(newValue, maxDecimalPlaces: 1)
                            }
                        Text("kg").foregroundStyle(.secondary).font(.caption)
                    }

                    Picker("Today's Workout", selection: $selectedWorkoutChoice) {
                        ForEach(routineDays) { day in
                            Text(day.label).tag(WorkoutChoice.day(day.id))
                        }
                        Text("Rest").tag(WorkoutChoice.rest)
                    }

                    ratingPicker(label: "Energy Level", selection: $energyLevel)
                    ratingPicker(label: "Soreness (DOMS)", selection: $sorenessLevel)

                    HStack {
                        Text("Sleep")
                        Spacer()
                        TextField("-", text: $yesterdaySleepHoursText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .onChange(of: yesterdaySleepHoursText) { _, newValue in
                                yesterdaySleepHoursText = Self.filteredDecimalText(newValue, maxDecimalPlaces: 2, max: 24)
                            }
                        Text("hrs").foregroundStyle(.secondary).font(.caption)
                    }
                }
                .listRowBackground(AppRowBackground())

                Section("Yesterday") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Hunger Levels")
                            .font(.subheadline)
                        Picker("Hunger Levels", selection: $yesterdayHungerLevel) {
                            ForEach(1...5, id: \.self) { value in
                                Text("\(value)").tag(Optional(value))
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        HStack {
                            Text("1 - not hungry")
                            Spacer()
                            Text("5 - starving")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    Toggle("Alcohol or off-plan meal?", isOn: $yesterdayOffPlan)

                    if yesterdayOffPlan {
                        TextField("What happened?", text: $yesterdayOffPlanNotes, axis: .vertical)
                            .lineLimit(2...4)
                    }
                }
                .listRowBackground(AppRowBackground())

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(AppColor.error)
                }
            }
            .appScreen()
            .navigationTitle("Daily Check-In")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .appToolbarTint()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save")
                        }
                    }
                    .disabled(isSaving)
                    .appToolbarTint()
                }
            }
            .task { await load() }
        }
        .interactiveDismissDisabled()
    }

    /// Keeps a decimal text field's typed input to digits, at most one
    /// decimal point, at most `maxDecimalPlaces` digits after it, and (if
    /// `max` is given) no higher than a plausible ceiling - so a value like
    /// weight, water, or sleep hours can't be saved with more precision
    /// than the app displays, or as an impossible number (e.g. "82.4"
    /// hours of sleep) just because nothing stopped the keystrokes.
    private static func filteredDecimalText(_ text: String, maxDecimalPlaces: Int, max: Double? = nil) -> String {
        var filtered = text.filter { $0.isNumber || $0 == "." }
        if let firstDot = filtered.firstIndex(of: ".") {
            var searchRange = filtered.index(after: firstDot)..<filtered.endIndex
            while let extraDot = filtered.range(of: ".", range: searchRange) {
                filtered.remove(at: extraDot.lowerBound)
                searchRange = extraDot.lowerBound..<filtered.endIndex
            }
        }
        if let dotIndex = filtered.firstIndex(of: "."),
           filtered.distance(from: filtered.index(after: dotIndex), to: filtered.endIndex) > maxDecimalPlaces {
            let cutoff = filtered.index(dotIndex, offsetBy: maxDecimalPlaces + 1)
            filtered = String(filtered[filtered.startIndex..<cutoff])
        }
        if let max, let value = Double(filtered), value > max {
            filtered = String(format: "%.\(maxDecimalPlaces)f", max)
        }
        return filtered
    }

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

    private func load() async {
        do {
            if let routine = try await routineRepository.fetchActiveRoutine() {
                routineDays = try await routineRepository.fetchDays(routineId: routine.id)
            }
            if let existing = try await checkinRepository.fetch(date: Date()) {
                weightText = existing.weightKg.map { String(format: "%.1f", $0) } ?? ""
                energyLevel = existing.energyLevel ?? 5
                sorenessLevel = existing.sorenessLevel ?? 1
                existingYesterdayWaterMl = existing.yesterdayWaterMl
                yesterdayOffPlan = existing.yesterdayOffPlan ?? false
                yesterdayOffPlanNotes = existing.yesterdayOffPlanNotes ?? ""
                yesterdayHungerLevel = existing.yesterdayHungerLevel
                if let routineDayId = existing.routineDayId {
                    selectedWorkoutChoice = .day(routineDayId)
                } else {
                    selectedWorkoutChoice = .rest
                }
            }
            // No weight typed in yet: use this morning's scale reading if there is one.
            if weightText.isEmpty,
               let todays = try? await BodyWeightRepository().fetchRecent(days: 1)
                   .last(where: { Calendar.current.isDateInToday($0.loggedAt) }) {
                weightText = String(format: "%.1f", todays.weightKg)
            }
            if let sleepLog = try await healthRepository.fetchSleepLog(date: Date()) {
                existingSleepLog = sleepLog
                yesterdaySleepHoursText = String(format: "%.2f", Double(sleepLog.totalSleepMinutes) / 60.0)
            } else {
                existingSleepLog = nil
                yesterdaySleepHoursText = ""
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }

        let weightKg = Double(weightText)
        var routineDayId: UUID?
        var workoutChoiceLabel: String?
        var isRest = false

        switch selectedWorkoutChoice {
        case .day(let id):
            routineDayId = id
            workoutChoiceLabel = routineDays.first(where: { $0.id == id })?.label
        case .rest:
            isRest = true
            workoutChoiceLabel = "Rest"
        }

        // Only a sleep figure the user changed is written back; one that
        // matches the Health sync is left alone.
        var sleepMinutes: Int?
        if let sleepHours = Double(yesterdaySleepHoursText) {
            let minutes = Int((sleepHours * 60).rounded())
            if existingSleepLog?.totalSleepMinutes != minutes { sleepMinutes = minutes }
        }

        let checkin = QueuedDailyCheckin(
            date: Date(),
            weightKg: weightKg,
            routineDayId: routineDayId,
            workoutChoiceLabel: workoutChoiceLabel,
            isRestDay: isRest,
            energyLevel: energyLevel,
            sorenessLevel: sorenessLevel,
            yesterdayWaterMl: existingYesterdayWaterMl,
            yesterdayOffPlan: yesterdayOffPlan,
            yesterdayOffPlanNotes: yesterdayOffPlan ? yesterdayOffPlanNotes : nil,
            yesterdayHungerLevel: yesterdayHungerLevel,
            sleepMinutes: sleepMinutes
        )

        do {
            try await DailyCheckinSubmitter.submit(checkin)
        } catch {
            // No connection: keep it on the phone and send it when back
            // online - the check-in counts as done either way.
            guard OfflineError.isConnectivity(error) else {
                errorMessage = error.localizedDescription
                return
            }
            OfflineOutbox.shared.enqueue(.dailyCheckin(checkin))
        }

        CheckinAvailabilityService.shared.checkinCompleted(.daily)
        await onSaved()
        dismiss()
    }
}
