import SwiftUI

struct WeeklyCheckinFlow: View {
    var onSaved: () async -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    // Page 1
    @State private var overallRating7d = 3
    @State private var weightText = ""
    @State private var activeGoal: UserGoal?
    @State private var weekNumber: Int?

    // Page 2
    @State private var energyLevel = 3
    @State private var sorenessLevel = 3
    @State private var stressLevel = 3
    @State private var stressReason = ""
    @State private var biggestWin = ""
    @State private var moodNotes = ""

    // Page 3
    @State private var overallAdherence = 3
    @State private var trainingAdherence = 3
    @State private var nutritionAdherence = 3
    @State private var disciplineLevel = 3
    @State private var upcomingDistractions = ""

    // Page 4
    @State private var savedCheckin: WeeklyCheckin?

    @State private var errorMessage: String?
    @State private var isSaving = false

    private let goalsRepository = GoalsRepository()
    private let checkinRepository = WeeklyCheckinRepository()
    private let measurementRepository = BodyMeasurementRepository()
    private let photoRepository = ProgressPhotoRepository()

    var body: some View {
        NavigationStack {
            Form {
                switch page {
                case 0: pageOne
                case 1: pageTwo
                case 2: pageThree
                default: pageFour
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Weekly Check-In (\(page + 1)/4)")
            .toolbar {
                if page < 3 {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button("Skip") { dismiss() }
                        Button(page == 2 ? "Save" : "Next") {
                            if page == 2 {
                                Task { await saveCheckin() }
                            } else {
                                page += 1
                            }
                        }
                        .disabled(isSaving)
                    }
                }
                if page > 0 && savedCheckin == nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back") { page -= 1 }
                    }
                }
            }
            .interactiveDismissDisabled()
            .task { await loadContext() }
        }
    }

    private var pageOne: some View {
        Section("This Week") {
            Text("Rate the previous 7 days")
            ratingPicker(selection: $overallRating7d)

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

    private var pageTwo: some View {
        Section("Biofeedback") {
            Text("Energy Level")
            ratingPicker(selection: $energyLevel)
            Text("Muscle Soreness")
            ratingPicker(selection: $sorenessLevel)
            Text("Stress Level")
            ratingPicker(selection: $stressLevel)

            TextField("Reason for stress this week (optional)", text: $stressReason, axis: .vertical)
                .lineLimit(2...4)
            TextField("Biggest win this week", text: $biggestWin, axis: .vertical)
                .lineLimit(2...4)
            TextField("General mood and mindset this week", text: $moodNotes, axis: .vertical)
                .lineLimit(2...4)
        }
    }

    private var pageThree: some View {
        Section("Adherence") {
            Text("Overall Adherence to Plan")
            ratingPicker(selection: $overallAdherence)
            Text("Training Adherence")
            ratingPicker(selection: $trainingAdherence)
            Text("Nutrition Adherence")
            ratingPicker(selection: $nutritionAdherence)
            Text("Discipline to Reach Goal")
            ratingPicker(selection: $disciplineLevel)

            TextField("Any distractions coming up?", text: $upcomingDistractions, axis: .vertical)
                .lineLimit(2...4)
        }
    }

    @ViewBuilder
    private var pageFour: some View {
        if let savedCheckin {
            Section {
                Text("Check-in saved.")
                    .font(.headline)
            }
            Section {
                MeasurementsPhotosCaptureView(
                    onSaveMeasurement: { waist, left, right in
                        try? await measurementRepository.log(
                            waistCm: waist,
                            leftBicepCm: left,
                            rightBicepCm: right,
                            goalId: activeGoal?.id,
                            weeklyCheckinId: savedCheckin.id,
                            source: "weekly_checkin"
                        )
                    },
                    onSavePhoto: { data in
                        try? await photoRepository.upload(
                            imageData: data,
                            takenAt: Date(),
                            goalId: activeGoal?.id,
                            weeklyCheckinId: savedCheckin.id
                        )
                    }
                )
            }
            Section {
                Button("Done") {
                    CheckinAvailabilityService.shared.checkinCompleted(.weekly)
                    dismiss()
                }
            }
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private func ratingPicker(selection: Binding<Int>) -> some View {
        Picker("", selection: selection) {
            ForEach(1...5, id: \.self) { value in
                Text("\(value)").tag(value)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func loadContext() async {
        do {
            activeGoal = try await goalsRepository.fetchCurrentGoal()
            if let activeGoal {
                let effectiveFromDate = ISO8601DateFormatter().date(from: activeGoal.effectiveFrom + "T00:00:00Z") ?? Date()
                let days = Calendar.current.dateComponents([.day], from: effectiveFromDate, to: Date()).day ?? 0
                weekNumber = max(1, days / 7 + 1)
            }
            if let mostRecent = try await checkinRepository.fetchMostRecent(), let weight = mostRecent.weightKg {
                weightText = String(weight)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveCheckin() async {
        isSaving = true
        defer { isSaving = false }

        do {
            let checkin = try await checkinRepository.save(
                date: Date(),
                goalId: activeGoal?.id,
                weekNumber: weekNumber,
                overallRating7d: overallRating7d,
                weightKg: Double(weightText),
                energyLevel: energyLevel,
                sorenessLevel: sorenessLevel,
                stressLevel: stressLevel,
                stressReason: stressReason.isEmpty ? nil : stressReason,
                biggestWin: biggestWin.isEmpty ? nil : biggestWin,
                moodNotes: moodNotes.isEmpty ? nil : moodNotes,
                overallAdherence: overallAdherence,
                trainingAdherence: trainingAdherence,
                nutritionAdherence: nutritionAdherence,
                disciplineLevel: disciplineLevel,
                upcomingDistractions: upcomingDistractions.isEmpty ? nil : upcomingDistractions
            )
            savedCheckin = checkin
            page = 3
            errorMessage = nil
            CheckinAvailabilityService.shared.checkinCompleted(.weekly)
            await onSaved()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
