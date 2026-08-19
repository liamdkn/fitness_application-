import Supabase
import SwiftUI

struct DailyCheckinSheet: View {
    var onSaved: () async -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var weightText = ""
    @State private var routineDays: [RoutineDay] = []
    @State private var selectedWorkoutChoice: WorkoutChoice = .rest
    @State private var energyLevel = 3
    @State private var sorenessLevel = 3
    @State private var yesterdayWaterText = ""
    @State private var yesterdayOffPlan = false
    @State private var yesterdayOffPlanNotes = ""
    @State private var yesterdaySleepHoursText = ""
    @State private var hasExistingSleepLog = false
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
                        Text("kg").foregroundStyle(.secondary).font(.caption)
                    }

                    Picker("Today's Workout", selection: $selectedWorkoutChoice) {
                        ForEach(routineDays) { day in
                            Text(day.label).tag(WorkoutChoice.day(day.id))
                        }
                        Text("Rest").tag(WorkoutChoice.rest)
                    }

                    ratingPicker(label: "Energy", selection: $energyLevel)
                    ratingPicker(label: "Soreness (DOMS)", selection: $sorenessLevel)

                    HStack {
                        Text("Sleep")
                        Spacer()
                        TextField("-", text: $yesterdaySleepHoursText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .disabled(hasExistingSleepLog)
                            .foregroundStyle(hasExistingSleepLog ? .secondary : .primary)
                        Text("hrs").foregroundStyle(.secondary).font(.caption)
                    }
                    if !hasExistingSleepLog {
                        Text("No sleep data synced for last night - add it manually if you know it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Yesterday") {
                    HStack {
                        Text("Water Intake")
                        Spacer()
                        TextField("-", text: $yesterdayWaterText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("ml").foregroundStyle(.secondary).font(.caption)
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

                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save Check-In")
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .navigationTitle("Daily Check-In")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") { dismiss() }
                }
            }
            .task { await load() }
        }
        .interactiveDismissDisabled()
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
                weightText = existing.weightKg.map { String($0) } ?? ""
                energyLevel = existing.energyLevel ?? 3
                sorenessLevel = existing.sorenessLevel ?? 3
                yesterdayWaterText = existing.yesterdayWaterMl.map { String($0) } ?? ""
                yesterdayOffPlan = existing.yesterdayOffPlan ?? false
                yesterdayOffPlanNotes = existing.yesterdayOffPlanNotes ?? ""
                if let routineDayId = existing.routineDayId {
                    selectedWorkoutChoice = .day(routineDayId)
                } else {
                    selectedWorkoutChoice = .rest
                }
            }
            if let sleepLog = try await healthRepository.fetchSleepLog(date: Date()) {
                hasExistingSleepLog = true
                yesterdaySleepHoursText = String(format: "%.1f", Double(sleepLog.totalSleepMinutes) / 60.0)
            } else {
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
                yesterdayWaterMl: Int(yesterdayWaterText),
                yesterdayOffPlan: yesterdayOffPlan,
                yesterdayOffPlanNotes: yesterdayOffPlan ? yesterdayOffPlanNotes : nil
            )

            if let weightKg, try await !bodyWeightRepository.hasLoggedToday() {
                try? await bodyWeightRepository.logWeight(kg: weightKg)
            }

            if let sleepHours = Double(yesterdaySleepHoursText) {
                let alreadyLogged = try await healthRepository.fetchSleepLog(date: Date()) != nil
                if !alreadyLogged {
                    let minutes = Int(sleepHours * 60)
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
