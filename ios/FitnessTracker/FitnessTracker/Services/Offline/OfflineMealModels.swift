import Foundation
import SwiftData

/// Local mirror of a `meal_entries` row, plus queue bookkeeping - see
/// `OfflineMealQueue`. Reuses `SyncState` from `OfflineWorkoutModels.swift`
/// rather than redefining an identical enum.
@Model
final class QueuedMealEntry {
    @Attribute(.unique) var id: UUID
    var date: String
    var mealSlotId: UUID
    var foodId: UUID?
    var recipeId: UUID?
    var quantity: Double
    var loggedAt: Date
    var syncState: SyncState
    var pendingDeletion: Bool

    init(
        id: UUID,
        date: String,
        mealSlotId: UUID,
        foodId: UUID?,
        recipeId: UUID?,
        quantity: Double,
        loggedAt: Date,
        syncState: SyncState
    ) {
        self.id = id
        self.date = date
        self.mealSlotId = mealSlotId
        self.foodId = foodId
        self.recipeId = recipeId
        self.quantity = quantity
        self.loggedAt = loggedAt
        self.syncState = syncState
        self.pendingDeletion = false
    }

    func asMealEntry() -> MealEntry {
        MealEntry(id: id, date: date, mealSlotId: mealSlotId, foodId: foodId, recipeId: recipeId, quantity: quantity, loggedAt: loggedAt)
    }
}
