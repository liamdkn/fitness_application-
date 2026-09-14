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
    @State private var yesterdayWaterText = ""
    @State private var yesterdayOffPlan = false
    @State private var yesterdayOffPlanNotes = ""
    @State private var yesterdaySleepHoursText = ""
    @State private var hasExistingSleepLog = false
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
                    if hasExistingSleepLog {
                        Text("Synced from Apple Health - edit if it's wrong.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Yesterday") {
                    HStack {
                        Text("Water Intake")
                        Spacer()
                        TextField("-", text: $yesterdayWaterText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .onChange(of: yesterdayWaterText) { _, newValue in
                                yesterdayWaterText = Self.filteredDecimalText(newValue, maxDecimalPlaces: 1)
                            }
                        Text("L").foregroundStyle(.secondary).font(.caption)
                    }

                    Toggle("Alcohol or off-plan meal?", isOn: $yesterdayOffPlan)

                    if yesterdayOffPlan {
                        TextField("What happened?", text: $yesterdayOffPlanNotes, axis: .vertical)
                            .lineLimit(2...4)
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Daily Check-In")
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
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
                yesterdayWaterText = existing.yesterdayWaterMl.map { String(format: "%.1f", Double($0) / 1000.0) } ?? ""
                yesterdayOffPlan = existing.yesterdayOffPlan ?? false
                yesterdayOffPlanNotes = existing.yesterdayOffPlanNotes ?? ""
                if let routineDayId = existing.routineDayId {
                    selectedWorkoutChoice = .day(routineDayId)
                } else {
                    selectedWorkoutChoice = .rest
                }
            }
            if let sleepLog = try await healthRepository.fetchSleepLog(date: Date()) {
                existingSleepLog = sleepLog
                hasExistingSleepLog = true
                yesterdaySleepHoursText = String(format: "%.2f", Double(sleepLog.totalSleepMinutes) / 60.0)
            } else {
                existingSleepLog = nil
                hasExistingSleepLog = false
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

        do {
            try await checkinRepository.save(
                date: Date(),
                weightKg: weightKg,
                routineDayId: routineDayId,
                workoutChoiceLabel: workoutChoiceLabel,
                isRestDay: isRest,
                energyLevel: energyLevel,
                sorenessLevel: sorenessLevel,
                yesterdayWaterMl: Double(yesterdayWaterText).map { Int(($0 * 1000).rounded()) },
                yesterdayOffPlan: yesterdayOffPlan,
                yesterdayOffPlanNotes: yesterdayOffPlan ? yesterdayOffPlanNotes : nil
            )

            if let weightKg, try await !bodyWeightRepository.hasLoggedToday() {
                try? await bodyWeightRepository.logWeight(kg: weightKg)
            }

            if let sleepHours = Double(yesterdaySleepHoursText) {
                let minutes = Int((sleepHours * 60).rounded())
                let unchangedFromSync = existingSleepLog?.totalSleepMinutes == minutes
                if !unchangedFromSync {
                    try? await healthRepository.upsertSleep([
                        SleepLog(
                            userId: try await SupabaseService.shared.client.auth.session.user.id,
                            date: DateFormatting.isoDate(Date()),
                            totalSleepMinutes: minutes,
                            inBedMinutes: minutes,
                            source: "manual"
                        )
                    ])
                }
            }

            CheckinAvailabilityService.shared.checkinCompleted(.daily)
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
