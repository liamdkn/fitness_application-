import Foundation
import SwiftData

/// Local-first write path for logging a meal, mirroring
/// `OfflineWorkoutQueue`'s pattern exactly: every add/delete lands in a
/// local SwiftData store first (fast, durable, can't fail for a
/// connectivity reason), then syncs to Supabase in the background -
/// immediately after the write, and again on reconnect. A client-generated
/// id is shared between the local row and its eventual Supabase row, so
/// replaying a sync after a partial failure just upserts the same row
/// rather than duplicating it.
///
/// Scope: covers adding and deleting a single entry - the two things
/// someone actually does standing at a meal with no signal. Bulk
/// operations that copy many entries at once (repeat day, apply a saved
/// meal/day) stay online-only through `MealEntryRepository` directly, the
/// same kind of boundary `OfflineWorkoutQueue` draws around historical
/// browsing: the rarer, less time-critical path doesn't need to pay for
/// full offline support to make the common one work.
@MainActor
final class OfflineMealQueue {
    static let shared = OfflineMealQueue()

    private let mealEntryRepository: MealEntryRepository
    private let networkMonitor: NetworkMonitor
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    private var isFlushing = false
    private var flushAgainRequested = false

    /// A week, not `OfflineWorkoutQueue`'s 2 days - meal entries get
    /// browsed further back (checking last week's Tuesday) more often than
    /// a finished workout does.
    private let pruneAfter: TimeInterval = 60 * 60 * 24 * 7
    private let periodicRetryInterval: TimeInterval = 20
    private var periodicRetryTask: Task<Void, Never>?

    init(mealEntryRepository: MealEntryRepository = MealEntryRepository(), networkMonitor: NetworkMonitor = .shared) {
        self.mealEntryRepository = mealEntryRepository
        self.networkMonitor = networkMonitor
        do {
            let configuration = ModelConfiguration(
                "meal-queue",
                schema: Schema([QueuedMealEntry.self]),
                url: URL.applicationSupportDirectory.appending(path: "meal-queue.store")
            )
            container = try ModelContainer(for: QueuedMealEntry.self, configurations: configuration)
        } catch {
            fatalError("Failed to create offline meal queue store: \(error)")
        }
        self.networkMonitor.onReconnected { [weak self] in
            self?.scheduleFlush()
        }
        scheduleFlush()
        startPeriodicRetry()
    }

    private func startPeriodicRetry() {
        periodicRetryTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(periodicRetryInterval * 1_000_000_000))
                await self.flushPendingChanges()
            }
        }
    }

    // MARK: - Entries

    @discardableResult
    func addFoodEntry(date: Date, mealSlotId: UUID, foodId: UUID, quantity: Double) throws -> MealEntry {
        try add(date: date, mealSlotId: mealSlotId, foodId: foodId, recipeId: nil, quantity: quantity)
    }

    @discardableResult
    func addRecipeEntry(date: Date, mealSlotId: UUID, recipeId: UUID, quantity: Double) throws -> MealEntry {
        try add(date: date, mealSlotId: mealSlotId, foodId: nil, recipeId: recipeId, quantity: quantity)
    }

    private func add(date: Date, mealSlotId: UUID, foodId: UUID?, recipeId: UUID?, quantity: Double) throws -> MealEntry {
        let local = QueuedMealEntry(
            id: UUID(),
            date: DateFormatting.isoDate(date),
            mealSlotId: mealSlotId,
            foodId: foodId,
            recipeId: recipeId,
            quantity: quantity,
            loggedAt: Date(),
            syncState: .pending
        )
        context.insert(local)
        try context.save()
        scheduleFlush()
        return local.asMealEntry()
    }

    /// Local-first: this date's pending (or synced-but-not-yet-pruned)
    /// local rows are merged with whatever Supabase returns, local always
    /// winning on a shared id since it's the more current copy while a
    /// flush is still catching up - so a day partly logged offline still
    /// shows everything the moment it's reopened, connected or not.
    func fetchEntries(date: Date) async throws -> [MealEntry] {
        let dateString = DateFormatting.isoDate(date)
        let localRows = try fetchLocalEntries(date: dateString)
        let remote = (try? await mealEntryRepository.fetchEntries(date: date)) ?? []

        var byId = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        for local in localRows {
            if local.pendingDeletion {
                byId.removeValue(forKey: local.id)
            } else {
                byId[local.id] = local.asMealEntry()
            }
        }
        return byId.values.sorted { $0.loggedAt < $1.loggedAt }
    }

    /// Correcting a mistyped amount after the fact (e.g. tapping a logged
    /// item to reopen its grams editor) - same local-first shape as
    /// `deleteEntry`: a still-`.pending` local row is edited in place and
    /// syncs on the next flush regardless; an already-`.synced` local row
    /// is reset back to `.pending` so the flush re-upserts it with the new
    /// quantity instead of leaving Supabase with the stale value.
    func updateQuantity(id: UUID, quantity: Double) async throws -> MealEntry {
        if let local = try fetchLocalEntry(id: id) {
            local.quantity = quantity
            if local.syncState == .synced {
                local.syncState = .pending
            }
            try context.save()
            scheduleFlush()
            return local.asMealEntry()
        } else {
            return try await mealEntryRepository.updateQuantity(id: id, quantity: quantity)
        }
    }

    func deleteEntry(id: UUID) async throws {
        if let local = try fetchLocalEntry(id: id) {
            if local.syncState == .pending {
                context.delete(local)
            } else {
                local.pendingDeletion = true
            }
            try context.save()
            scheduleFlush()
        } else {
            // Not something this queue is tracking (already synced and
            // pruned, or logged in a different session) - outside this
            // queue's write surface, same online-only boundary as bulk
            // operations.
            try await mealEntryRepository.deleteEntry(id: id)
        }
    }

    // MARK: - Local lookups

    private func fetchLocalEntries(date: String) throws -> [QueuedMealEntry] {
        try context.fetch(FetchDescriptor<QueuedMealEntry>(predicate: #Predicate { $0.date == date }))
    }

    private func fetchLocalEntry(id: UUID) throws -> QueuedMealEntry? {
        var descriptor = FetchDescriptor<QueuedMealEntry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    // MARK: - Sync

    private func scheduleFlush() {
        Task { await flushPendingChanges() }
    }

    func flushPendingChanges() async {
        guard !isFlushing else {
            flushAgainRequested = true
            return
        }
        isFlushing = true
        defer { isFlushing = false }

        repeat {
            flushAgainRequested = false
            guard networkMonitor.isConnected else { return }

            guard let entries = try? context.fetch(FetchDescriptor<QueuedMealEntry>()) else { return }
            for entry in entries {
                await flush(entry)
            }
            try? context.save()
        } while flushAgainRequested

        pruneOldSyncedEntries()
        try? context.save()
    }

    private func flush(_ entry: QueuedMealEntry) async {
        if entry.pendingDeletion {
            do {
                try await mealEntryRepository.deleteEntry(id: entry.id)
                context.delete(entry)
            } catch {
                // Still offline, or a genuine failure - leave the
                // tombstone in place and retry on the next flush.
            }
            return
        }

        if entry.syncState == .pending {
            do {
                try await mealEntryRepository.upsertEntry(
                    id: entry.id,
                    date: entry.date,
                    mealSlotId: entry.mealSlotId,
                    foodId: entry.foodId,
                    recipeId: entry.recipeId,
                    quantity: entry.quantity,
                    loggedAt: entry.loggedAt
                )
                entry.syncState = .synced
            } catch {
                // Retry on the next flush.
            }
        }
    }

    /// Local rows are only needed for offline-safe reads/edits for a
    /// couple of days after logging - once fully synced and past
    /// `pruneAfter`, Supabase is the only copy that needs to exist.
    private func pruneOldSyncedEntries() {
        guard let entries = try? context.fetch(FetchDescriptor<QueuedMealEntry>()) else { return }
        let cutoff = Date().addingTimeInterval(-pruneAfter)
        for entry in entries {
            guard entry.syncState == .synced, entry.loggedAt < cutoff else { continue }
            context.delete(entry)
        }
    }
}
