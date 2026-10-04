import SwiftUI

/// Carbs toward the preworkout target, plus one-tap suggestions: usual
/// preworkout foods sized to the carbs still to go. Shown on the Preworkout
/// meal only.
struct PreworkoutCarbCard: View {
    let carbsG: Double
    let targetG: Double
    let slotName: String
    let onLog: (Food, Double) -> Void

    @State private var suggestions: [Food] = []

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
                if !suggestions.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(suggestions) { food in
                            if let servings = PreworkoutCarbs.servings(of: food, forCarbsG: remaining) {
                                suggestionRow(food, servings: servings)
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

    private func suggestionRow(_ food: Food, servings: Double) -> some View {
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
        var found: [Food] = []
        for keyword in Self.keywords {
            guard let hits = try? await repository.browse(query: keyword, limit: 40) else { continue }
            if let best = hits.first(where: { !$0.isDrink && !$0.isQuickAdd && $0.carbsG > 0.5 && $0.name.localizedCaseInsensitiveContains(keyword.split(separator: " ")[0]) }) {
                found.append(best)
            }
        }
        suggestions = found
    }
}
