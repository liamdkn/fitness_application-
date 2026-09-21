import SwiftUI

/// The dedicated screen for `NutritionSource.inHouse` - day-level calorie/
/// macro progress at a glance, with every meal slot's summary right below
/// it (tapping one opens that slot's own logging, `MealSlotDetailView`). A
/// sibling to `NutritionEntryView`, not a mode of it: `NutritionSource`
/// picks which one loads (see `MainTabView`'s `NutritionTabView`), so this
/// owns everything meal-log-specific instead of branching inline the way
/// the old combined screen did.
struct MealLogHomeView: View {
    @State private var selectedDate = Date()
    @State private var goal: UserGoal?
    @State private var showingRepeatDay = false
    @State private var showingSavedDaysPicker = false
    @State private var showingSaveDay = false
    @State private var addingFoodToSlot: MealSlot?
    @StateObject private var viewModel = MealLogViewModel()
    private let goalsRepository = GoalsRepository()

    private var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    private var totals: DayMacroTotals { viewModel.dayTotals }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    dateHeader

                    CalorieProgressBar(logged: totals.calories, target: goal?.dailyCalorieTarget)

                    HStack(spacing: 12) {
                        MacroProgressCard(label: "Protein", value: totals.proteinG, target: goal?.proteinGTarget, color: .blue)
                        MacroProgressCard(label: "Carbs", value: totals.carbsG, target: goal?.carbsGTarget, color: .green)
                        MacroProgressCard(label: "Fat", value: totals.fatG, target: goal?.fatGTarget, color: .yellow)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Meals")
                            .font(.title3.bold())
                        ForEach(viewModel.slotGroups) { group in
                            MealSlotCard(
                                group: group,
                                date: selectedDate,
                                viewModel: viewModel,
                                onLogTapped: { addingFoodToSlot = group.slot }
                            )
                        }
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .navigationTitle("Nutrition")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Repeat Yesterday") {
                            Task { await viewModel.repeatDay(from: Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate, to: selectedDate) }
                        }
                        Button("Repeat a Day...") { showingRepeatDay = true }
                        Button("Apply a Saved Day...") { showingSavedDaysPicker = true }
                        if !viewModel.entries.isEmpty {
                            Button("Save This Day") { showingSaveDay = true }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .task {
                await viewModel.loadMealSlots()
                await viewModel.loadEntries(date: selectedDate)
                await loadGoal()
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
        HStack {
            Button { changeDay(by: -1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            DatePicker("", selection: $selectedDate, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.compact)
                .labelsHidden()
                .onChange(of: selectedDate) { _, newDate in
                    Task {
                        await viewModel.loadEntries(date: newDate)
                        await loadGoal()
                    }
                }
            Spacer()
            Button { changeDay(by: 1) } label: { Image(systemName: "chevron.right") }
                .disabled(isToday)
        }
    }

    private func changeDay(by offset: Int) {
        guard let newDate = Calendar.current.date(byAdding: .day, value: offset, to: selectedDate) else { return }
        selectedDate = newDate
        Task {
            await viewModel.loadEntries(date: newDate)
            await loadGoal()
        }
    }

    /// Point-in-time, not "whatever's active today" - matches
    /// `NutritionEntryView.loadGoal()`'s own reasoning: the date picker
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
                } else {
                    Text("\(Int(logged)) kcal")
                        .foregroundStyle(.secondary)
                }
            }
            ProgressView(value: progress)
                .tint(.orange)
        }
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
    let group: MealSlotGroup
    let date: Date
    @ObservedObject var viewModel: MealLogViewModel
    let onLogTapped: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                MealSlotDetailView(viewModel: viewModel, slot: group.slot, date: date)
            } label: {
                MealSlotSummaryContent(group: group)
            }
            .buttonStyle(.plain)

            HStack {
                Spacer()
                Button(action: onLogTapped) {
                    Text(group.entries.isEmpty ? "Log" : "Log more")
                        .font(.subheadline.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(.blue.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
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
                Text("\(quantityLabel(entry.entry.quantity)) \u{00d7} \(entry.servingLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Int(entry.calories))")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }

    private func quantityLabel(_ quantity: Double) -> String {
        quantity == quantity.rounded() ? "\(Int(quantity))" : String(format: "%.1f", quantity)
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
            ProgressView(value: progress)
                .tint(color)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
    }
}
