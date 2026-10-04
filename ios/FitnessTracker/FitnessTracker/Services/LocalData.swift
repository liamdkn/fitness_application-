import Foundation
import UserNotifications
import WidgetKit

/// Everything the app keeps on the phone is one account's - cached foods and
/// preferences, queued writes, widget numbers, scheduled reminders. This is
/// what keeps it that way: when a different account signs in (or anyone signs
/// out) the lot is cleared, so one person's data is never shown to, or sent
/// as, someone else.
@MainActor
enum LocalData {
    private static let ownerKey = "local-data-owner"

    /// Called whenever a session is known. A different user than last time
    /// wipes everything first. The first time this has ever run, whoever's
    /// signed in is taken to be the phone's owner (the data already here is
    /// theirs) and nothing is cleared.
    static func claim(_ userId: UUID) {
        let stored = UserDefaults.standard.string(forKey: ownerKey)
        if let stored, stored != userId.uuidString {
            wipe()
        } else if stored == nil {
            OfflineOutbox.shared.adoptUnowned(by: userId)
        }
        UserDefaults.standard.set(userId.uuidString, forKey: ownerKey)
    }

    /// Writes made here that the server hasn't confirmed yet.
    static var unsentCount: Int {
        OfflineOutbox.shared.entries.count + OfflineMealQueue.shared.unsyncedCount + OfflineWorkoutQueue.shared.unsyncedCount
    }

    /// Tries once to send everything waiting. A no-op with no connection.
    static func flushAll() async {
        await OfflineOutbox.shared.flush()
        await OfflineMealQueue.shared.flushPendingChanges()
        await OfflineWorkoutQueue.shared.flushPendingChanges()
    }

    /// Clears every local copy of the signed-in account's data.
    static func wipe() {
        OfflineReferenceCache.removeAll()
        Caches.resetAll()
        OfflineOutbox.shared.wipeAll()
        OfflineMealQueue.shared.wipeAll()
        OfflineWorkoutQueue.shared.wipeAll()
        BedtimeResolver.invalidate()
        PendingWater.clear()
        UserDefaults.standard.removeObject(forKey: "milk-allowance-applied-date")
        UserDefaults.standard.removeObject(forKey: ownerKey)
        WidgetSnapshot.clear()
        WidgetCenter.shared.reloadAllTimelines()
        // Reminders carry the old account's numbers; the next account's are
        // scheduled fresh when its app opens.
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        Task { await WorkoutLiveActivityManager.shared.end() }
        Task { await SupplementReminderService.shared.clear() }
        CardioSessionMonitor.shared.sessionEnded()
    }
}
