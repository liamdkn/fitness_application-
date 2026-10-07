import SwiftUI

/// Carbs toward the preworkout target, plus one-tap suggestions: usual
/// preworkout foods sized to the carbs still to go. Shown on the Preworkout
/// meal only.
struct PreworkoutCarbCard: View {
    let carbsG: Double
    let targetG: Double
    let slotName: String
    let mealSlotId: UUID
    let date: Date
    let onLog: (Food, Double) -> Void

    @State private var suggestions: [Food] = []
    @State private var usualFoods: [Food] = []
    @State private var loggedDayCounts: [UUID: Int] = [:]

    /// Searched for in the food database; the first food with carbs in each
    /// is offered.
    private static let keywords = ["cocopops", "honey", "dates", "rice cake", "banana", "rice krispie"]

    private var remaining: Double { max(targetG - carbsG, 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Preworkout carbs")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(carbsG.rounded())) / \(Int(targetG)) g")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            AppProgressBar(value: min(carbsG / max(targetG, 1), 1))
                .tint(AppColor.carbs)
            if remaining < 1 {
                Label("Target reached", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(AppColor.success)
            } else {
                Text("\(Int(remaining.rounded())) g to go. Tap one to log enough to get there.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !usualFoods.isEmpty {
                    Label("Foods you often use", systemImage: "sparkles")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    VStack(spacing: 8) {
                        ForEach(usualFoods) { food in
                            if let servings = PreworkoutCarbs.servings(of: food, forCarbsG: remaining) {
                                suggestionRow(food, servings: servings, detail: "Used on \(loggedDayCounts[food.id, default: 0]) recent days")
                            }
                        }
                    }
                }
                if !suggestions.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(suggestions.filter { suggestion in !usualFoods.contains(where: { usual in usual.id == suggestion.id }) }) { food in
                            if let servings = PreworkoutCarbs.servings(of: food, forCarbsG: remaining) {
                                suggestionRow(food, servings: servings, detail: nil)
                            }
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: 16)
        .task { await loadSuggestions() }
    }

    private func suggestionRow(_ food: Food, servings: Double, detail: String?) -> some View {
        Button {
            onLog(food, servings)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(food.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(food.amountLabel(at: servings))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let detail {
                        Text(detail).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Text("\(Int(food.carbsG(at: servings).rounded())) g carbs")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(AppColor.accent)
            }
        }
        .buttonStyle(.plain)
    }

    private func loadSuggestions() async {
        let repository = FoodRepository()
        await loadUsualFoods()
        var found: [Food] = []
        for keyword in Self.keywords {
            guard let hits = try? await repository.browse(query: keyword, limit: 40) else { continue }
            if let best = hits.first(where: { !$0.isDrink && !$0.isQuickAdd && $0.carbsG > 0.5 && $0.name.localizedCaseInsensitiveContains(keyword.split(separator: " ")[0]) }) {
                found.append(best)
            }
        }
        suggestions = found
    }

    /// Rank foods previously logged to this workout's Preworkout slot by
    /// the number of distinct recent days they appeared. This turns the
    /// carb helper into a personal suggestion while keeping the generic
    /// starter ideas available when logging history is sparse.
    private func loadUsualFoods() async {
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: date)
        guard let start = calendar.date(byAdding: .day, value: -27, to: end),
              let entries = try? await MealEntryRepository().fetchEntries(from: start, to: end) else { return }

        var daysByFood: [UUID: Set<String>] = [:]
        for entry in entries where entry.mealSlotId == mealSlotId {
            guard let foodId = entry.foodId else { continue }
            daysByFood[foodId, default: []].insert(entry.date)
        }
        let ranked = daysByFood
            .filter { $0.value.count >= 2 }
            .sorted { $0.value.count > $1.value.count }
            .prefix(4)
        guard !ranked.isEmpty,
              let foods = try? await FoodRepository().fetchByIds(ranked.map(\.key)) else { return }
        let foodById = Dictionary(uniqueKeysWithValues: foods.map { ($0.id, $0) })
        let ordered = ranked.compactMap { foodById[$0.key] }
            .filter { !$0.isDrink && !$0.isQuickAdd && $0.carbsG > 0 }
        usualFoods = ordered
        loggedDayCounts = Dictionary(uniqueKeysWithValues: ranked.map { ($0.key, $0.value.count) })
    }
}
