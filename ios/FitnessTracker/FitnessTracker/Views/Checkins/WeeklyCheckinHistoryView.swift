import SwiftUI

/// Everything a past weekly check-in recorded, reachable from Settings ->
/// Weekly Check-In -> Check-In History. This is purely a browse/review
/// screen (nothing here is editable) - the check-in itself is only ever
/// created through `WeeklyCheckinFlow`.
struct WeeklyCheckinHistoryView: View {
    @State private var checkins: [WeeklyCheckin] = []
    @State private var errorMessage: String?
    @State private var isLoading = false
    @State private var context = CheckinContext(goals: [], weeks: [:])

    private let repository = WeeklyCheckinRepository()
    private let goalsRepository = GoalsRepository()
    private let weeklyLogRepository = WeeklyLogRepository()

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(AppColor.error)
            }
            ForEach(Array(checkins.enumerated()), id: \.element.id) { index, checkin in
                // Newest first, so the previous check-in is the next one down.
                let previous = index + 1 < checkins.count ? checkins[index + 1] : nil
                NavigationLink {
                    WeeklyCheckinDetailView(checkin: checkin, previous: previous, context: context)
                } label: {
                    row(for: checkin, previous: previous)
                }
            }
        }
        .overlay {
            if isLoading && checkins.isEmpty {
                ProgressView()
            } else if !isLoading && checkins.isEmpty && errorMessage == nil {
                ContentUnavailableView("No Check-Ins Yet", systemImage: "calendar.badge.clock", description: Text("Your weekly check-ins will show up here once you complete one."))
            }
        }
        .appScreen()
        .navigationTitle("Check-In History")
        .task { await load() }
    }

    @ViewBuilder
    private func row(for checkin: WeeklyCheckin, previous: WeeklyCheckin?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(formattedDate(checkin.checkinDate))
                    .font(.headline)
                Spacer()
                if let weight = checkin.weightKg {
                    Text(String(format: "%.1f kg", weight))
                        .font(.subheadline.weight(.semibold))
                }
            }
            if let phase = context.phaseLabel(for: checkin) {
                Text(phase)
                    .font(.caption)
                    .foregroundStyle(AppColor.accent)
            }
            HStack(spacing: 12) {
                if let weight = checkin.weightKg, let before = previous?.weightKg {
                    let change = weight - before
                    Text(String(format: "%+.1f kg on last check-in", change))
                }
                if let week = context.week(for: checkin) {
                    if let calories = week.avgCalories { Text("\(Int(calories.rounded())) kcal/day") }
                    if let steps = week.avgSteps { Text("\(Int(steps.rounded()).formatted()) steps/day") }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            checkins = try await repository.fetchRecent()
            errorMessage = nil
            let goals = ((try? await goalsRepository.fetchPastGoals(limit: 100)) ?? [])
                .sorted { $0.effectiveFrom < $1.effectiveFrom }
            let weeks = (try? await weeklyLogRepository.fetchSummary(limit: 104, before: nil)) ?? []
            context = CheckinContext(goals: goals, weeks: Dictionary(weeks.map { ($0.weekStart, $0) }, uniquingKeysWith: { first, _ in first }))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formattedDate(_ isoDate: String) -> String {
        guard let date = DateFormatting.date(fromISODate: isoDate) else { return isoDate }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

/// One check-in's full record: the weight/week it was logged with, any
/// measurements and photos captured against it (via
/// `MeasurementsPhotosCaptureView` at the end of the flow), and - for an
/// older check-in from before the survey was retired - its old subjective
/// answers, reusing the same `WeeklyCheckinSummary` Weekly Insights shows.
struct WeeklyCheckinDetailView: View {
    let checkin: WeeklyCheckin
    var previous: WeeklyCheckin?
    var context = CheckinContext(goals: [], weeks: [:])

    @State private var measurements: [BodyMeasurement] = []
    @State private var photos: [ProgressPhoto] = []
    @State private var photoURLs: [UUID: URL] = [:]
    @State private var errorMessage: String?

    private let measurementRepository = BodyMeasurementRepository()
    private let photoRepository = ProgressPhotoRepository()

    var body: some View {
        Form {
            Section("This Check-In") {
                if let weight = checkin.weightKg {
                    LabeledContent("Weight", value: String(format: "%.1f kg", weight))
                }
                if let weekNumber = checkin.weekNumber {
                    LabeledContent("Week", value: "\(weekNumber)")
                }
            }
            .listRowBackground(AppRowBackground())

            if let goal = context.goal(for: checkin) {
                Section("Phase") {
                    if let phase = context.phaseLabel(for: checkin) {
                        LabeledContent("Phase", value: phase)
                    }
                    LabeledContent("Targets", value: "\(Int(goal.dailyCalorieTarget)) kcal, \(Int(goal.proteinGTarget)) g protein")
                    if let rate = goal.weeklyWeightChangeKg {
                        LabeledContent("Planned change", value: String(format: "%+.2f kg a week", rate))
                    }
                    if let weight = checkin.weightKg, let before = previous?.weightKg, let was = previous {
                        let days = daysBetween(was.checkinDate, checkin.checkinDate)
                        LabeledContent("Since last check-in", value: String(format: "%+.1f kg over %d days", weight - before, days))
                    }
                }
                .listRowBackground(AppRowBackground())
            }

            if let week = context.week(for: checkin) {
                weekSection(week, goal: context.goal(for: checkin))
            }

            if !measurements.isEmpty {
                Section("Measurements") {
                    ForEach(measurements) { measurement in
                        VStack(alignment: .leading, spacing: 4) {
                            if let waist = measurement.waistCm {
                                LabeledContent("Waist", value: String(format: "%.1f cm", waist))
                            }
                            if let left = measurement.leftBicepCm {
                                LabeledContent("Left Bicep", value: String(format: "%.1f cm", left))
                            }
                            if let right = measurement.rightBicepCm {
                                LabeledContent("Right Bicep", value: String(format: "%.1f cm", right))
                            }
                        }
                    }
                }
                .listRowBackground(AppRowBackground())
            }

            if checkin.hasSurveyContent {
                Section("Notes From This Week") {
                    WeeklyCheckinSummary(checkin: checkin)
                }
                .listRowBackground(AppRowBackground())
            }

            if !photos.isEmpty {
                Section("Photos") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(photos) { photo in
                                photoThumbnail(photo)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                }
                .listRowBackground(AppRowBackground())
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(AppColor.error)
            }
        }
        .appScreen()
        .navigationTitle(formattedDate(checkin.checkinDate))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func daysBetween(_ from: String, _ to: String) -> Int {
        guard let a = DateFormatting.date(fromISODate: from), let b = DateFormatting.date(fromISODate: to) else { return 0 }
        return Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0
    }

    /// The week the check-in looks back on: averages against targets, and
    /// against the week before.
    private func weekSection(_ week: WeeklyLogEntry, goal: UserGoal?) -> some View {
        let before = context.previousWeek(of: week)
        return Section("The week before (from \(week.weekStartDate.formatted(.dateTime.day().month(.abbreviated))))") {
            if let weight = week.avgWeightKg {
                let spread = week.weightSpreadKg.map { String(format: " \u{00b1} %.1f", $0) } ?? ""
                let change = before?.avgWeightKg.map { String(format: " (%+.1f on the week before)", weight - $0) } ?? ""
                LabeledContent("Average weight", value: String(format: "%.1f", weight) + spread + " kg" + change)
            }
            if let calories = week.avgCalories {
                LabeledContent("Calories a day", value: versus(calories, target: goal?.dailyCalorieTarget, unit: "kcal"))
            }
            if let protein = week.avgProteinG {
                LabeledContent("Protein a day", value: versus(protein, target: goal?.proteinGTarget, unit: "g"))
            }
            if let carbs = week.avgCarbsG {
                LabeledContent("Carbs a day", value: versus(carbs, target: goal?.carbsGTarget, unit: "g"))
            }
            if let fat = week.avgFatG {
                LabeledContent("Fat a day", value: versus(fat, target: goal?.fatGTarget, unit: "g"))
            }
            if let steps = week.avgSteps {
                LabeledContent("Steps a day", value: versus(steps, target: goal?.stepTarget.map(Double.init), unit: ""))
            }
        }
        .listRowBackground(AppRowBackground())
    }

    /// "2,430 kcal (target 2,500)".
    private func versus(_ value: Double, target: Double?, unit: String) -> String {
        let suffix = unit.isEmpty ? "" : " " + unit
        let base = "\(Int(value.rounded()).formatted())\(suffix)"
        guard let target, target > 0 else { return base }
        return base + " (target \(Int(target.rounded()).formatted()))"
    }

    @ViewBuilder
    private func photoThumbnail(_ photo: ProgressPhoto) -> some View {
        Group {
            if let url = photoURLs[photo.id] {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Image(systemName: "photo").foregroundStyle(.secondary)
                    default:
                        ProgressView()
                    }
                }
            } else {
                ProgressView()
            }
        }
        .frame(width: 120, height: 160)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func load() async {
        do {
            async let measurementsResult = measurementRepository.fetchForWeeklyCheckin(checkin.id)
            async let photosResult = photoRepository.fetchForWeeklyCheckin(checkin.id)
            measurements = try await measurementsResult
            photos = try await photosResult
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        // Signed URLs are fetched one at a time, after the photo rows
        // themselves are already showing (each thumbnail shows its own
        // spinner until its URL resolves) rather than blocking the whole
        // screen on every URL coming back together.
        for photo in photos {
            if let url = try? await photoRepository.signedURL(path: photo.storagePath) {
                photoURLs[photo.id] = url
            }
        }
    }

    private func formattedDate(_ isoDate: String) -> String {
        guard let date = DateFormatting.date(fromISODate: isoDate) else { return isoDate }
        return date.formatted(date: .long, time: .omitted)
    }
}
