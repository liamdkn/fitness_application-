import SwiftUI

/// "Copy": a meal as it was on recent days - yesterday's lunch, the day
/// before's - to log again in one tap. The source meal can be any meal, not
/// just this one, so lunch can be copied to dinner and back (today's other
/// meals are offered too). Each day shows what was in it and its calories;
/// tapping Log adds every item to this meal as new entries, so editing them
/// never touches the original.
struct CopyMealView: View {
    private struct PastMeal: Identifiable {
        let date: Date
        let items: [MealSlotEntry]
        var id: Date { date }
        var calories: Double { items.reduce(0) { $0 + $1.calories } }
    }

    let slot: MealSlot
    /// Every meal, to pick the one to copy from.
    let slots: [MealSlot]
    /// Called with the chosen day's entries; the screen logs them to the meal.
    let onCopy: ([MealEntry]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sourceSlotId: UUID?
    @State private var allEntries: [MealEntry] = []
    @State private var foods: [UUID: Food] = [:]
    @State private var recipes: [UUID: Recipe] = [:]
    @State private var meals: [PastMeal] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    /// Items already copied one by one, so each shows a tick instead of a plus.
    @State private var copiedIds: Set<UUID> = []

    /// How far back to look.
    private static let lookbackDays = 14

    var body: some View {
        NavigationStack {
            List {
                Picker("Copy from", selection: Binding(
                    get: { sourceSlotId ?? slot.id },
                    set: { sourceSlotId = $0; rebuild() }
                )) {
                    ForEach(slots) { option in
                        Text(option.id == slot.id ? "\(option.name) (this meal)" : option.name).tag(option.id)
                    }
                }
                .listRowBackground(AppRowBackground())

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(AppColor.error)
                        .listRowBackground(Color.clear)
                }
                if meals.isEmpty && !isLoading {
                    Text("Nothing logged for \(sourceName.lowercased()) in the last \(Self.lookbackDays) days.")
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                ForEach(meals) { meal in
                    Section {
                        ForEach(meal.items) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).foregroundStyle(Color.primary)
                                    Text(item.amountLabel)
                                        .font(.caption)
                                        .foregroundStyle(Color.secondary)
                                }
                                Spacer()
                                Text("\(Int(item.calories.rounded()))")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.secondary)
                                    .monospacedDigit()
                                // Just this one food, without leaving - add several, one by one.
                                Button {
                                    onCopy([item.entry])
                                    copiedIds.insert(item.entry.id)
                                } label: {
                                    Image(systemName: copiedIds.contains(item.entry.id) ? "checkmark.circle.fill" : "plus.circle")
                                        .font(.title3)
                                        .foregroundStyle(copiedIds.contains(item.entry.id) ? AppColor.success : AppColor.accent)
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Add \(item.title)")
                            }
                        }
                        Button {
                            onCopy(meal.items.map(\.entry))
                            dismiss()
                        } label: {
                            Label("Log all \(meal.items.count) - \(Int(meal.calories.rounded())) kcal", systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.appPrimaryCompact)
                        .listRowBackground(Color.clear)
                    } header: {
                        Text(Self.dayLabel(meal.date))
                    }
                    .listRowBackground(AppRowBackground())
                }
            }
            .appScreen()
            .navigationTitle("Copy to \(slot.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .appToolbarTint()
                }
            }
            .task { await load() }
        }
    }

    private var sourceName: String {
        slots.first { $0.id == (sourceSlotId ?? slot.id) }?.name ?? slot.name
    }

    private func load() async {
        defer { isLoading = false }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let from = calendar.date(byAdding: .day, value: -Self.lookbackDays, to: today) else { return }
        do {
            // Through today: another meal's entries from today can be copied here.
            allEntries = try await OfflineMealQueue.shared.fetchEntries(from: from, to: today)
            foods = Dictionary(uniqueKeysWithValues: try await FoodRepository()
                .fetchByIds(Array(Set(allEntries.compactMap(\.foodId)))).map { ($0.id, $0) })
            recipes = Dictionary(uniqueKeysWithValues: try await RecipeRepository()
                .fetchByIds(Array(Set(allEntries.compactMap(\.recipeId)))).map { ($0.id, $0) })
            rebuild()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The days that have the chosen source meal. Copying a meal onto itself
    /// leaves today out (it'd just double it up).
    private func rebuild() {
        let source = sourceSlotId ?? slot.id
        let todayString = DateFormatting.isoDate(Date())
        let entries = allEntries.filter {
            $0.mealSlotId == source && !(source == slot.id && $0.date == todayString)
        }
        do {
            let byDate = Dictionary(grouping: entries, by: \.date)
            meals = byDate.compactMap { dateString, dayEntries -> PastMeal? in
                guard let date = DateFormatting.date(fromISODate: dateString) else { return nil }
                let items = dayEntries.sorted { $0.loggedAt < $1.loggedAt }.map {
                    MealSlotEntry(
                        entry: $0,
                        food: $0.foodId.flatMap { foods[$0] },
                        recipe: $0.recipeId.flatMap { recipes[$0] }
                    )
                }
                return PastMeal(date: date, items: items)
            }
            .sorted { $0.date > $1.date }
        }
    }

    private static func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }
}
