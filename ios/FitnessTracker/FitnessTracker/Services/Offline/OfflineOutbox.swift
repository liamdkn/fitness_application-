import Foundation
import Supabase

/// Everything a daily check-in writes, captured so it can be sent later:
/// the check-in row, the weigh-in, and the sleep entry.
struct QueuedDailyCheckin: Codable {
    let date: Date
    let weightKg: Double?
    let routineDayId: UUID?
    let workoutChoiceLabel: String?
    let isRestDay: Bool
    let energyLevel: Int
    let sorenessLevel: Int
    let yesterdayWaterMl: Int?
    let yesterdayOffPlan: Bool
    let yesterdayOffPlanNotes: String?
    /// Only set when the user changed it - an unchanged Health-synced value
    /// isn't written back.
    let sleepMinutes: Int?
}

/// The three writes a daily check-in makes, in order. Used when saving
/// normally and when replaying one that was queued offline - connection
/// failures propagate (so the caller can queue or retry), anything else on the
/// weight and sleep steps is ignored as before.
enum DailyCheckinSubmitter {
    @MainActor
    static func submit(_ checkin: QueuedDailyCheckin) async throws {
        try await DailyCheckinRepository().save(
            date: checkin.date,
            weightKg: checkin.weightKg,
            routineDayId: checkin.routineDayId,
            workoutChoiceLabel: checkin.workoutChoiceLabel,
            isRestDay: checkin.isRestDay,
            energyLevel: checkin.energyLevel,
            sorenessLevel: checkin.sorenessLevel,
            yesterdayWaterMl: checkin.yesterdayWaterMl,
            yesterdayOffPlan: checkin.yesterdayOffPlan,
            yesterdayOffPlanNotes: checkin.yesterdayOffPlanNotes
        )

        if let weightKg = checkin.weightKg {
            let bodyWeight = BodyWeightRepository()
            var updated: BodyWeightLog?
            do {
                updated = try await bodyWeight.updateTodaysWeight(kg: weightKg)
            } catch {
                if OfflineError.isConnectivity(error) { throw error }
            }
            if updated == nil {
                do {
                    _ = try await bodyWeight.logWeight(kg: weightKg)
                } catch {
                    if OfflineError.isConnectivity(error) { throw error }
                }
            }
        }

        if let minutes = checkin.sleepMinutes {
            do {
                try await HealthRepository().upsertSleep([
                    SleepLog(
                        userId: try await SupabaseService.shared.client.auth.session.user.id,
                        date: DateFormatting.isoDate(checkin.date),
                        totalSleepMinutes: minutes,
                        inBedMinutes: minutes,
                        source: "manual"
                    )
                ])
            } catch {
                if OfflineError.isConnectivity(error) { throw error }
            }
        }
    }
}

/// A small persistent queue of writes made with no signal - water logs and
/// daily check-ins (with their weigh-in and sleep) - sent in order when the
/// connection returns. Meals and workouts have their own, richer queues
/// (`OfflineMealQueue`, `OfflineWorkoutQueue`); this covers the smaller ones.
/// Every operation is safe to replay: water logs carry a client-made id and
/// are upserted, deletes are by id, and a check-in is an upsert per day.
@MainActor
final class OfflineOutbox {
    static let shared = OfflineOutbox()

    enum Operation: Codable {
        case addWater(WaterLog)
        case deleteWater(UUID)
        case dailyCheckin(QueuedDailyCheckin)
    }

    struct Entry: Codable {
        let id: UUID
        let operation: Operation
        var attempts: Int
        /// Who queued it. Never sent under anyone else's session. `nil` only
        /// for entries saved before owners were recorded (see `adoptUnowned`).
        var ownerId: UUID?
    }

    private(set) var entries: [Entry] = []
    private var isFlushing = false
    private var retryTask: Task<Void, Never>?
    private static let maxAttempts = 5
    private static let retryInterval: TimeInterval = 20

    private let fileURL = URL.applicationSupportDirectory.appending(path: "offline-outbox.json")

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
        }
        NetworkMonitor.shared.onReconnected { [weak self] in
            Task { await self?.flush() }
        }
        if !entries.isEmpty { scheduleRetry() }
    }

    var hasPending: Bool { !entries.isEmpty }

    func enqueue(_ operation: Operation) {
        entries.append(Entry(id: UUID(), operation: operation, attempts: 0, ownerId: SupabaseService.shared.session?.user.id))
        persist()
        scheduleRetry()
    }

    // MARK: Water, as the screens should see it while writes are pending

    /// A water log that hasn't reached the server yet is dropped outright if
    /// it's deleted - it never needs to. Returns true when that happened.
    /// Entries from before owners were recorded belong to the one person who
    /// has been using this phone: give them to the account that's signed in now.
    func adoptUnowned(by userId: UUID) {
        var changed = false
        for index in entries.indices where entries[index].ownerId == nil {
            entries[index].ownerId = userId
            changed = true
        }
        if changed { persist() }
    }

    /// Removes everything queued - at sign-out or when a different account
    /// signs in (see `LocalData`).
    func wipeAll() {
        entries = []
        retryTask?.cancel()
        retryTask = nil
        try? FileManager.default.removeItem(at: fileURL)
    }

    func cancelPendingAddWater(id: UUID) -> Bool {
        guard let index = entries.firstIndex(where: {
            if case .addWater(let log) = $0.operation { return log.id == id }
            return false
        }) else { return false }
        entries.remove(at: index)
        persist()
        return true
    }

    /// `logs` for `date` with pending adds included and pending deletes hidden.
    func applyingPendingWater(to logs: [WaterLog], date: String) -> [WaterLog] {
        var result = logs
        var deletedIds = Set<UUID>()
        for entry in entries {
            switch entry.operation {
            case .addWater(let log) where log.date == date && !result.contains(where: { $0.id == log.id }):
                result.append(log)
            case .deleteWater(let id):
                deletedIds.insert(id)
            default:
                break
            }
        }
        return result.filter { !deletedIds.contains($0.id) }.sorted { $0.loggedAt < $1.loggedAt }
    }

    // MARK: Sending

    func flush() async {
        guard !isFlushing, !entries.isEmpty else { return }
        isFlushing = true
        defer { isFlushing = false }

        // Entries queued by someone else can never be sent as the current user:
            // drop them rather than write another person's data into this account.
        guard let currentUser = SupabaseService.shared.session?.user.id else { return }
        let before = entries.count
        entries.removeAll { $0.ownerId != nil && $0.ownerId != currentUser }
        if entries.count != before { persist() }

        while let first = entries.first {
            guard first.ownerId == currentUser else {
                // No recorded owner: can't be vouched for, so it isn't sent.
                entries.removeFirst()
                persist()
                continue
            }
            do {
                try await perform(first.operation)
                entries.removeFirst()
                persist()
            } catch {
                if !OfflineError.isConnectivity(error) {
                    // A real rejection: try a few times, then give up on it so
                    // one bad entry can't hold up everything behind it.
                    entries[0].attempts += 1
                    if entries[0].attempts >= Self.maxAttempts { entries.removeFirst() }
                    persist()
                }
                break
            }
        }
        if entries.isEmpty { retryTask?.cancel() } else { scheduleRetry() }
    }

    private func perform(_ operation: Operation) async throws {
        switch operation {
        case .addWater(let log):
            try await WaterRepository().upsertLog(log)
        case .deleteWater(let id):
            try await WaterRepository().deleteLogOnServer(id: id)
        case .dailyCheckin(let checkin):
            try await DailyCheckinSubmitter.submit(checkin)
        }
    }

    private func scheduleRetry() {
        guard retryTask == nil || retryTask?.isCancelled == true else { return }
        retryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.retryInterval * 1_000_000_000))
                guard let self, !Task.isCancelled else { return }
                if self.entries.isEmpty { self.retryTask = nil; return }
                await self.flush()
            }
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            // Best effort - the in-memory queue still works for this session.
        }
    }
}
