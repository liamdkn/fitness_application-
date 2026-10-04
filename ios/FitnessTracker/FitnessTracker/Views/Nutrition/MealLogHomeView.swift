import SwiftUI

/// The Nutrition tab's only screen now - day-level calorie/macro progress
/// at a glance, with every meal slot's summary right below it (tapping one
/// opens that slot's own logging, `MealSlotDetailView`). Everything shown
/// is what's been logged here - nothing is pulled in from Apple Health or
/// another food app any more.
struct MealLogHomeView: View {
    @State private var selectedDate = Date()
    @State private var goal: UserGoal?
    @State private var showingRepeatDay = false
    @State private var showingSavedDaysPicker = false
    @State private var showingSaveDay = false
    @State private var addingFoodToSlot: MealSlot?
    @State private var showingDatePicker = false
    /// ISO dates (within the visible week) that have at least one entry -
    /// what paints a checkmark on `WeekDayStrip`'s other 6 days. The
    /// currently-selected day doesn't need its own entry here; it reads
    /// `viewModel.entries` directly (see `isLogged`), so its checkmark is
    /// never a fetch behind the entries actually on screen.
    @State private var loggedDateStrings: Set<String> = []
    @Namespace private var zoomNamespace
    /// Every planned treat in `weekDates` - fetched a week at a time since
    /// that's the unit `CalorieBankCalculator` redistributes across (a
    /// treat funds itself from the *other* days in its own week, not from
    /// next week's budget).
    @State private var weekTreats: [PlannedTreat] = []
    @StateObject private var viewModel = MealLogViewModel()
    /// Sodium and caffeine limits for the bars under the macro cards.
    @State private var preferences: UserPreferences?
    private let preferencesRepository = UserPreferencesRepository()
    private let goalsRepository = GoalsRepository()
    private let mealEntryRepository = MealEntryRepository()
    private let plannedTreatRepository = PlannedTreatRepository()

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    /// Monday-first, matching the MFP-style week strip below the title -
    /// this app's other week-based logic (weekly check-in, weekly schedule)
    /// doesn't care which day a week "starts" on, so there's no existing
    /// convention this needs to match instead.
    private var weekDates: [Date] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    /// The day's totals - just the meal log.
    private var totals: DayMacroTotals {
        viewModel.dayTotals
    }

    private var bankAdjustment: CalorieBankCalculator.DailyAdjustment {
        CalorieBankCalculator.adjustment(for: selectedDate, weekDates: weekDates, treats: weekTreats)
    }

    /// The day's calorie/macro targets after banking - what `CalorieProgressBar`/
    /// `MacroProgressCard` actually compare `totals` against, so a treat
    /// day's ring reads against its raised target rather than looking
    /// permanently "over."
    private var adjustedCalorieTarget: Double? {
        goal.map { $0.dailyCalorieTarget + bankAdjustment.calorieDelta }
    }
    private var adjustedProteinTarget: Double? {
        goal.map { $0.proteinGTarget + bankAdjustment.proteinDelta }
    }
    private var adjustedCarbsTarget: Double? {
        goal?.carbsGTarget.map { $0 + bankAdjustment.carbsDelta }
    }
    private var adjustedFatTarget: Double? {
        goal?.fatGTarget.map { $0 + bankAdjustment.fatDelta }
    }

    var body: some View {
        AppNavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    dateHeader

                    CalorieProgressBar(logged: totals.calories, target: adjustedCalorieTarget)

                    HStack(spacing: 12) {
                        MacroProgressCard(label: "Protein", value: totals.proteinG, target: adjustedProteinTarget, color: AppColor.protein)
                        MacroProgressCard(label: "Carbs", value: totals.carbsG, target: adjustedCarbsTarget, color: AppColor.carbs)
                        MacroProgressCard(label: "Fat", value: totals.fatG, target: adjustedFatTarget, color: AppColor.fat)
                    }

                    SodiumCaffeineRow(
                        sodiumMg: totals.sodiumMg,
                        sodiumLimitMg: preferences?.sodiumLimitMg ?? 2300,
                        caffeineMg: totals.caffeineMg,
                        caffeineLimitMg: preferences?.caffeineLimitMg ?? 400
                    )

                    if !bankAdjustment.treatsToday.isEmpty || !bankAdjustment.fundedTreats.isEmpty {
                        CalorieBankBanner(adjustment: bankAdjustment)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Meals")
                                .font(.title3.bold())
                            Spacer()
                            Menu {
                                Button("Repeat Yesterday") {
                                    Task { await viewModel.repeatDay(from: Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate, to: selectedDate) }
                                }
                                Button("Repeat a Day...") { showingRepeatDay = true }
                                Button("Apply a Saved Day...") { showingSavedDaysPicker = true }
                                if !viewModel.entries.isEmpty {
                                    Button("Save This Day") { showingSaveDay = true }
                                }
                                NavigationLink("Recipes...") { MealPrepListView() }
                                NavigationLink("Brand Compare...") { FoodGroupsView() }
                                NavigationLink("Weekly Treats...") { TreatsPlannerView() }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ForEach(viewModel.slotGroups) { group in
                            MealSlotCard(
                                zoom: zoomNamespace,
                                group: group,
                                date: selectedDate,
                                viewModel: viewModel,
                                plannedTreats: bankAdjustment.treatsToday.filter { $0.mealSlotId == group.slot.id },
                                onLogTapped: { addingFoodToSlot = group.slot }
                            )
                        }
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage).foregroundStyle(AppColor.error)
                    }
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.loadMealSlots()
                await viewModel.loadEntries(date: selectedDate)
                await loadGoal()
                await loadWeekLogStatus()
                await loadWeekTreats()
                preferences = try? await preferencesRepository.fetch()
            }
            .sheet(isPresented: $showingRepeatDay) {
                RepeatDaySheet(targetDate: selectedDate) { sourceDate in
                    Task { await viewModel.repeatDay(from: sourceDate, to: selectedDate) }
                }
            }
            .sheet(isPresented: $showingSavedDaysPicker) {
                SavedDaysPickerView { items in
                    Task { await viewModel.applySavedDay(items, date: selectedDate) }
                }
            }
            .sheet(isPresented: $showingSaveDay) {
                SaveDaySheet(totals: viewModel.dayTotals, entries: viewModel.entries) {}
            }
            .sheet(item: $addingFoodToSlot) { slot in
                FoodPickerView(mealSlotName: slot.name) { food, quantity in
                    Task { await viewModel.logFood(food, quantity: quantity, mealSlotId: slot.id, date: selectedDate) }
                }
            }
        }
    }

    private var dateHeader: some View {
        VStack(spacing: 14) {
            HStack {
                Text(isToday ? "Today" : headerDateText)
                    .font(.title2.bold())
                Spacer()
                Button {
                    showingDatePicker = true
                } label: {
                    Image(systemName: "calendar")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }

            WeekDayStrip(dates: weekDates, selectedDate: selectedDate, isLogged: isLogged, onSelect: selectDay)
        }
        .sheet(isPresented: $showingDatePicker) {
            NavigationStack {
                DatePicker("Date", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .labelsHidden()
                    .padding()
                    .appScreen()
                    .navigationTitle("Jump to Date")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showingDatePicker = false }
                            .appToolbarTint()
                        }
                    }
                    .onChange(of: selectedDate) { _, newDate in
                        showingDatePicker = false
                        Task {
                            await viewModel.loadEntries(date: newDate)
                            await loadGoal()
                            await loadWeekLogStatus()
                                        await loadWeekTreats()
                        }
                    }
                Spacer()
            }
            .presentationDetents([.medium])
        }
    }

    private var headerDateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, d MMM"
        return formatter.string(from: selectedDate)
    }

    /// The selected day always reflects `viewModel.entries` (already loaded,
    /// never stale); the other 6 days in the strip fall back to the
    /// batched `loggedDateStrings` from `loadWeekLogStatus()`.
    private func isLogged(_ date: Date) -> Bool {
        if Calendar.current.isDate(date, inSameDayAs: selectedDate) {
            return !viewModel.entries.isEmpty
        }
        return loggedDateStrings.contains(DateFormatting.isoDate(date))
    }

    private func selectDay(_ date: Date) {
        selectedDate = date
        Task {
            await viewModel.loadEntries(date: date)
            await loadGoal()
        }
    }

    /// Advisory only, like the Train tab's deload/volume checks - a plain
    /// presence check per day (any entry at all), not a full macro fetch,
    /// since the strip only ever needs to answer "logged or not".
    private func loadWeekLogStatus() async {
        guard let start = weekDates.first, let end = weekDates.last else { return }
        if let entries = try? await mealEntryRepository.fetchEntries(from: start, to: end) {
            loggedDateStrings = Set(entries.map(\.date))
        }
    }

    private func loadWeekTreats() async {
        guard let start = weekDates.first, let end = weekDates.last else { return }
        weekTreats = (try? await plannedTreatRepository.fetchTreats(from: start, to: end)) ?? []
    }

    /// Point-in-time, not "whatever's active today" - the date picker
    /// above can look at a past day, and its targets should reflect
    /// whatever phase was actually active then.
    private func loadGoal() async {
        let allGoals = ((try? await goalsRepository.fetchPastGoals(limit: 100)) ?? [])
            .sorted { $0.effectiveFrom < $1.effectiveFrom }
        let isoDate = DateFormatting.isoDate(selectedDate)
        goal = allGoals.last { $0.effectiveFrom <= isoDate }
    }
}

private struct CalorieProgressBar: View {
    let logged: Double
    let target: Double?

    private var progress: Double {
        guard let target, target > 0 else { return 0 }
        return min(logged / target, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Calories").font(.headline)
                Spacer()
                if let target {
                    Text("\(Int(logged)) / \(Int(target)) kcal")
                        .foregroundStyle(.secondary)
                        .rolling(Double(logged))
                } else {
                    Text("\(Int(logged)) kcal")
                        .foregroundStyle(.secondary)
                        .rolling(Double(logged))
                }
            }
            AppProgressBar(value: progress)
                .tint(AppColor.treat)
        }
    }
}

/// Explains *why* today's targets moved, on either side of a banked
/// treat - the treat's own day ("+900 kcal banked here today") or one of
/// the days funding it elsewhere in the week ("-150 kcal, saving toward
/// Cinnabon on Sat"). Without this, a raised or trimmed ring reads as a
/// silent, unexplained change from the goal's real targets.
private struct CalorieBankBanner: View {
    let adjustment: CalorieBankCalculator.DailyAdjustment

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(adjustment.treatsToday) { treat in
                Label("\(treat.label): +\(Int(treat.extraCalories)) kcal banked for today", systemImage: "gift.fill")
            }
            ForEach(adjustment.fundedTreats) { treat in
                Label("Saving toward \(treat.label) on \(weekdayName(treat.date))", systemImage: "arrow.down.circle")
            }
        }
        .font(.caption)
        .foregroundStyle(AppColor.treat)
    }

    private func weekdayName(_ isoDate: String) -> String {
        guard let date = DateFormatting.date(fromISODate: isoDate) else { return isoDate }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

/// One meal slot's card - the summary content (title/macros/itemized
/// entries) is its own `NavigationLink` to `MealSlotDetailView`, and
/// "Log"/"Log more" is a real, separate `Button` straight to
/// `FoodPickerView` - not text nested inside that same NavigationLink's
/// label. They're siblings in this VStack, not one nested inside the
/// other's tappable area, which is what actually caused mis-attributed
/// taps elsewhere in this app (see `SetLogGridView`,
/// `WeeklyInsightsView`'s week nav - both were a control embedded *inside*
/// another control's row/label); two plainly-separate, non-overlapping
/// controls in a VStack don't have that problem.
private struct MealSlotCard: View {
    let zoom: Namespace.ID
    let group: MealSlotGroup
    let date: Date
    @ObservedObject var viewModel: MealLogViewModel
    /// Treats banked onto *this* slot today, if any - see `CalorieBankCalculator`.
    let plannedTreats: [PlannedTreat]
    let onLogTapped: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                MealSlotDetailView(viewModel: viewModel, slot: group.slot, date: date)
                    .zoomDestination(id: group.slot.id, in: zoom)
            } label: {
                MealSlotSummaryContent(group: group)
            }
            .buttonStyle(.plain)
            .zoomSource(id: group.slot.id, in: zoom)

            ForEach(plannedTreats) { treat in
                Label("\(treat.label) - +\(Int(treat.extraCalories)) kcal banked", systemImage: "gift.fill")
                    .font(.caption)
                    .foregroundStyle(AppColor.treat)
            }

            HStack {
                Spacer()
                Button(action: onLogTapped) {
                    Text(group.entries.isEmpty ? "Log" : "Log more")
                }
                .buttonStyle(.appSecondaryCompact)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: 12)
    }
}

private struct MealSlotSummaryContent: View {
    let group: MealSlotGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.slot.name)
                    .font(.headline)
                Spacer()
                if group.totalCalories > 0 {
                    Text("\(Int(group.totalCalories)) cal")
                        .font(.headline)
                        .rolling(group.totalCalories)
                }
            }

            if group.entries.isEmpty {
                Text("Nothing logged yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                macroSummary
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(group.entries) { entry in
                        entryRow(entry)
                    }
                }
            }
        }
        .contentShape(Rectangle())
    }

    private var macroSummary: some View {
        HStack(spacing: 14) {
            macroText("C", group.totalCarbsG)
            macroText("F", group.totalFatG)
            macroText("P", group.totalProteinG)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func macroText(_ label: String, _ grams: Double) -> some View {
        HStack(spacing: 3) {
            Text(label).fontWeight(.bold)
            Text("\(Int(grams))g")
        }
    }

    private func entryRow(_ entry: MealSlotEntry) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                Text(entry.amountLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(entry.calories))")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

}

/// Sodium against its daily limit, and today's caffeine. (Sodium only counts
/// foods that have a figure on record.)
private struct SodiumCaffeineRow: View {
    let sodiumMg: Double
    let sodiumLimitMg: Int
    let caffeineMg: Double
    let caffeineLimitMg: Int

    var body: some View {
        HStack(spacing: 12) {
            metric("Sodium", value: sodiumMg, limit: Double(sodiumLimitMg), color: AppColor.sodium)
            metric("Caffeine", value: caffeineMg, limit: Double(caffeineLimitMg), color: AppColor.caffeine)
        }
    }

    private func metric(_ label: String, value: Double, limit: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(Int(value.rounded()).formatted()) / \(Int(limit).formatted()) mg")
                .font(.subheadline.bold())
                .monospacedDigit()
                .rolling(value)
            AppProgressBar(value: min(value / max(limit, 1), 1))
                .tint(value > limit ? AppColor.danger : color)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: 12)
    }
}

private struct MacroProgressCard: View {
    let label: String
    let value: Double
    let target: Double?
    let color: Color

    private var progress: Double {
        guard let target, target > 0 else { return 0 }
        return min(value / target, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(target.map { "\(Int(value))/\(Int($0))g" } ?? "\(Int(value))g")
                .font(.subheadline.bold())
                .rolling(value)
            AppProgressBar(value: progress)
                .tint(color)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: 12)
    }
}

/// The MFP-style "M T W T F S S" row under the date header - a small dot
/// marks the real-world today (distinct from whichever day is currently
/// selected, which this app tracks but MFP's own diary doesn't need to),
/// the selected day's letter is bold/tinted, and each circle fills with a
/// checkmark once that day has at least one entry logged. Every day in the
/// week is tappable, including ones later than today - planning or
/// pre-logging a future day is a real use case, not a mistake to block.
private struct WeekDayStrip: View {
    let dates: [Date]
    let selectedDate: Date
    let isLogged: (Date) -> Bool
    let onSelect: (Date) -> Void

    private let calendar = Calendar.current

    var body: some View {
        HStack(spacing: 0) {
            ForEach(dates, id: \.self) { date in
                dayColumn(date)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func dayColumn(_ date: Date) -> some View {
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(date)
        let logged = isLogged(date)

        VStack(spacing: 6) {
            Circle()
                .fill(isToday ? Color.secondary : .clear)
                .frame(width: 4, height: 4)

            Text(weekdayLetter(date))
                .font(.caption.weight(isSelected ? .bold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)

            Button {
                onSelect(date)
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? AppColor.accent : Color.secondary.opacity(0.3), lineWidth: isSelected ? 2 : 1)
                        .background(Circle().fill(logged ? AppColor.accent.opacity(0.15) : .clear))
                    if logged {
                        Image(systemName: "checkmark")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppColor.accent)
                    }
                }
                .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
    }

    private func weekdayLetter(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter.string(from: date)
    }
}
