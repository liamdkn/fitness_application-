import SwiftUI

/// The calorie bank's home screen - this week's total calorie/macro budget
/// up top, every treat currently planned against it below, addable/removable
/// from here. Framed the way the idea actually works day to day: a treat
/// "comes off" the week's total (shown as a running remainder), not "some
/// days quietly get smaller" - `CalorieBankCalculator` is what turns these
/// plans into each day's adjusted target on `MealLogHomeView`, but this
/// screen only manages the plans themselves against the week-level picture.
struct TreatsPlannerView: View {
    @State private var goal: UserGoal?
    @State private var mealSlots: [MealSlot] = []
    @State private var treats: [PlannedTreat] = []
    @State private var showingPlanTreat = false
    @State private var errorMessage: String?
    private let goalsRepository = GoalsRepository()
    private let mealSlotsRepository = MealSlotsRepository()
    private let plannedTreatRepository = PlannedTreatRepository()

    /// Always the current calendar week (Monday-first, matching
    /// `MealLogHomeView`'s own week) - this screen manages what's coming
    /// up, not whatever day happens to be selected on the log screen.
    private var weekDates: [Date] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var weeklyCalorieBudget: Double? { goal.map { $0.dailyCalorieTarget * 7 } }
    private var bankedCalories: Double { treats.reduce(0) { $0 + $1.extraCalories } }

    /// Distinct calendar dates carrying a treat - a day with two treats
    /// still only counts once, since it's still one day funded by the
    /// others, not two.
    private var treatDayCount: Int {
        let calendar = Calendar.current
        let treatDays = treats.compactMap { treat in
            DateFormatting.date(fromISODate: treat.date).map { calendar.startOfDay(for: $0) }
        }
        return Set(treatDays).count
    }

    /// What a normal (non-treat) day's calorie target becomes once every
    /// treat's surplus is spread across the other days - the average over
    /// those days, which is also the exact figure whenever a single treat
    /// is the only one banked this week (the common case).
    private var newDailyCalories: Double? {
        guard let dailyTarget = goal?.dailyCalorieTarget else { return nil }
        let nonTreatDays = max(weekDates.count - treatDayCount, 1)
        return dailyTarget - bankedCalories / Double(nonTreatDays)
    }

    var body: some View {
        List {
            Section {
                weeklyHeader
            }
            .listRowBackground(Color.clear)

            Section("Planned Treats") {
                if bankedCalories > 0 {
                    plannedTreatsSummary
                }
                if treats.isEmpty {
                    Text("Nothing banked this week - add a treat and its calories/macros come off the totals above, spread out of the other days to compensate.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(treats) { treat in
                        treatRow(treat)
                    }
                    .onDelete(perform: deleteTreats)
                }
            }
            .listRowBackground(AppRowBackground())

            Section("Per Day, After Treats") {
                ForEach(weekDates, id: \.self) { date in
                    dayBreakdownRow(date)
                }
            }
            .listRowBackground(AppRowBackground())

            if let errorMessage {
                Text(errorMessage).foregroundStyle(AppColor.error)
            }
        }
        .appScreen()
        .navigationTitle("Weekly Treats")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingPlanTreat = true
                } label: {
                    Image(systemName: "plus")
                }
                .appToolbarTint()
            }
        }
        .task { await load() }
        .sheet(isPresented: $showingPlanTreat) {
            PlanTreatSheet(weekDates: weekDates, mealSlots: mealSlots) {
                await loadTreats()
            }
        }
    }

    @ViewBuilder
    private var weeklyHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Weekly Calories")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                if let weeklyCalorieBudget {
                    Text("\(Int(weeklyCalorieBudget - bankedCalories)) / \(Int(weeklyCalorieBudget)) kcal")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                } else {
                    Text("Set a goal in My Goals to see your weekly budget.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var plannedTreatsSummary: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(Int(bankedCalories)) kcal banked for treats")
                .font(.caption)
                .foregroundStyle(AppColor.warning)
            if let newDailyCalories, let dailyTarget = goal?.dailyCalorieTarget {
                Text("New \(Int(newDailyCalories)) / Old \(Int(dailyTarget)) kcal per day")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// One day's actual target after `CalorieBankCalculator` applies every
    /// treat in the week - raised on a treat's own day, trimmed on a day
    /// funding someone else's, unchanged on a plain day. Same calculation
    /// `MealLogHomeView` uses for that one day at a time; this is the same
    /// thing laid out for the whole week at once.
    @ViewBuilder
    private func dayBreakdownRow(_ date: Date) -> some View {
        let adjustment = CalorieBankCalculator.adjustment(for: date, weekDates: weekDates, treats: treats)
        let isToday = Calendar.current.isDateInToday(date)

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(dayOfWeekLabel(date))
                    .font(.subheadline.weight(isToday ? .bold : .regular))
                if !adjustment.treatsToday.isEmpty {
                    Image(systemName: "gift.fill")
                        .font(.caption2)
                        .foregroundStyle(AppColor.warning)
                }
                Spacer()
                if let goal {
                    Text("\(Int(goal.dailyCalorieTarget + adjustment.calorieDelta)) kcal")
                        .font(.subheadline.bold())
                        .foregroundStyle(colorForDelta(adjustment.calorieDelta))
                }
            }

            if let goal {
                HStack(spacing: 14) {
                    macroChip("P", goal.proteinGTarget + adjustment.proteinDelta)
                    if let carbs = goal.carbsGTarget {
                        macroChip("C", carbs + adjustment.carbsDelta)
                    }
                    if let fat = goal.fatGTarget {
                        macroChip("F", fat + adjustment.fatDelta)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private func colorForDelta(_ delta: Double) -> Color {
        if delta > 0 { return AppColor.warning }
        if delta < 0 { return .secondary }
        return .primary
    }

    private func macroChip(_ label: String, _ value: Double) -> some View {
        HStack(spacing: 3) {
            Text(label).fontWeight(.bold)
            Text("\(Int(value))g")
        }
    }

    private func dayOfWeekLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date)
    }

    private func treatRow(_ treat: PlannedTreat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(treat.label).font(.headline)
                Spacer()
                Text("+\(Int(treat.extraCalories)) kcal").foregroundStyle(.secondary)
            }
            Text(mealSlotName(treat.mealSlotId).map { "\(dayLabel(treat.date)) - \($0)" } ?? dayLabel(treat.date))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func mealSlotName(_ id: UUID?) -> String? {
        guard let id else { return nil }
        return mealSlots.first { $0.id == id }?.name
    }

    private func dayLabel(_ isoDate: String) -> String {
        guard let date = DateFormatting.date(fromISODate: isoDate) else { return isoDate }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMM"
        return formatter.string(from: date)
    }

    private func load() async {
        await loadGoal()
        mealSlots = (try? await mealSlotsRepository.fetchAll()) ?? []
        await loadTreats()
    }

    /// Today's active goal - this screen only ever shows/manages the
    /// current week, so unlike `MealLogHomeView` (which can look at any
    /// past day) there's no historical goal to resolve here.
    private func loadGoal() async {
        let allGoals = ((try? await goalsRepository.fetchPastGoals(limit: 100)) ?? [])
            .sorted { $0.effectiveFrom < $1.effectiveFrom }
        let isoDate = DateFormatting.isoDate(Date())
        goal = allGoals.last { $0.effectiveFrom <= isoDate }
    }

    private func loadTreats() async {
        guard let start = weekDates.first, let end = weekDates.last else { return }
        do {
            treats = try await plannedTreatRepository.fetchTreats(from: start, to: end)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteTreats(at offsets: IndexSet) {
        let toDelete = offsets.map { treats[$0] }
        treats.remove(atOffsets: offsets)
        Task {
            for treat in toDelete {
                do {
                    try await plannedTreatRepository.deleteTreat(id: treat.id)
                } catch {
                    errorMessage = error.localizedDescription
                    await loadTreats()
                }
            }
        }
    }
}
