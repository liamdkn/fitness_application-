import Foundation

/// Adds the daily milk allowance - the milk that goes in tea and coffee - to
/// today's Drinks meal, once per day.
///
/// It's an ordinary meal entry (so calories, hydration and the rest count with
/// no special cases, and changing it for one day is just editing or removing
/// that entry). The default amount lives in preferences. "Once per day" is
/// remembered both on the server and on the phone: a day's entry that was
/// deleted on purpose isn't put back, and working offline can't add it twice.
/// It's added when the app is opened that day - a day the app isn't opened
/// gets no allowance.
@MainActor
enum MilkAllowanceService {
    private static let localKey = "milk-allowance-applied-date"

    static func applyIfNeeded() async {
        guard let preferences = try? await UserPreferencesRepository().fetch(),
              preferences.milkAllowanceEnabled,
              let foodId = preferences.milkFoodId,
              preferences.milkAllowanceMl > 0 else { return }

        let today = DateFormatting.isoDate(Date())
        if preferences.milkAppliedDate == today || UserDefaults.standard.string(forKey: localKey) == today { return }

        guard let food = (try? await FoodRepository().fetchByIds([foodId]))?.first,
              let slot = try? await LiquidsRepository().drinksSlot() else { return }

        // Quantity is a multiplier on the food's own serving (100 ml serving: 100 ml = 1).
        let quantity = Double(preferences.milkAllowanceMl) / max(food.servingSize, 1)
        do {
            try OfflineMealQueue.shared.addFoodEntry(date: Date(), mealSlotId: slot.id, foodId: foodId, quantity: quantity)
        } catch {
            return
        }
        UserDefaults.standard.set(today, forKey: localKey)
        try? await UserPreferencesRepository().markMilkApplied(date: today)
        await WidgetSnapshotService.shared.refresh(force: true)
    }
}
