import Foundation
import Supabase

struct WaterRepository {
    let client = SupabaseService.shared.client

    private struct NewContainer: Encodable {
        let user_id: UUID
        let name: String
        let volume_ml: Int
    }

    private struct UpdateContainer: Encodable {
        let name: String
        let volume_ml: Int
    }

    /// Carries the client-made id and time so the same log can be sent more
    /// than once (an offline retry) without being duplicated.
    private struct UpsertLog: Encodable {
        let id: UUID
        let user_id: UUID
        let date: String
        let amount_ml: Int
        let container_id: UUID?
        let logged_at: Date
    }

    func fetchContainers() async throws -> [WaterContainer] {
        try await cachedRead(key: "water-containers") {
            try await client
                .from("water_containers")
                .select()
                .order("name")
                .execute()
                .value
        }
    }

    @discardableResult
    func createContainer(name: String, volumeMl: Int) async throws -> WaterContainer {
        let userId = try await client.auth.session.user.id
        let inserted: [WaterContainer] = try await client
            .from("water_containers")
            .insert(NewContainer(user_id: userId, name: name, volume_ml: volumeMl))
            .select()
            .execute()
            .value
        guard let container = inserted.first else {
            throw RepositoryError.insertFailed
        }
        return container
    }

    @discardableResult
    func updateContainer(id: UUID, name: String, volumeMl: Int) async throws -> WaterContainer {
        let updated: [WaterContainer] = try await client
            .from("water_containers")
            .update(UpdateContainer(name: name, volume_ml: volumeMl))
            .eq("id", value: id)
            .select()
            .execute()
            .value
        guard let container = updated.first else {
            throw RepositoryError.insertFailed
        }
        return container
    }

    /// A container referenced by a past log isn't hard-deleted along with it
    /// - the log's `container_id` just goes null (`on delete set null`),
    /// since that log's own `amount_ml` was already copied at log time and
    /// doesn't depend on the container still existing.
    func deleteContainer(id: UUID) async throws {
        try await client
            .from("water_containers")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    /// The day's logs, including any not yet sent to the server (added while
    /// offline) and without any whose deletion is still waiting to be sent.
    /// With no connection, the last copy fetched for that day stands in.
    func fetchLogs(date: Date) async throws -> [WaterLog] {
        let dateString = DateFormatting.isoDate(date)
        let key = "water-logs-\(dateString)"
        let logs: [WaterLog]
        do {
            logs = try await client
                .from("water_logs")
                .select()
                .eq("date", value: dateString)
                .order("logged_at")
                .execute()
                .value
            OfflineReferenceCache.save(logs, key: key)
        } catch {
            guard OfflineError.isConnectivity(error) else { throw error }
            return OfflineOutbox.shared.applyingPendingWater(
                to: OfflineReferenceCache.load([WaterLog].self, key: key) ?? [],
                date: dateString
            )
        }
        return OfflineOutbox.shared.applyingPendingWater(to: logs, date: dateString)
    }

    /// Every log within an inclusive calendar range - same shape as
    /// `NutritionRepository.fetchRange`/`MealEntryRepository.fetchEntries(from:to:)`,
    /// what Weekly Insights' avg-water-per-day figure is built from.
    func fetchLogs(from: Date, to: Date) async throws -> [WaterLog] {
        try await client
            .from("water_logs")
            .select()
            .gte("date", value: DateFormatting.isoDate(from))
            .lte("date", value: DateFormatting.isoDate(to))
            .order("date")
            .execute()
            .value
    }

    /// Saved with a client-made id. With no connection it's queued
    /// (`OfflineOutbox`) and shows up in the day's logs straight away.
    @discardableResult
    func addLog(date: Date, amountMl: Int, containerId: UUID?) async throws -> WaterLog {
        let log = WaterLog(
            id: UUID(),
            date: DateFormatting.isoDate(date),
            amountMl: amountMl,
            containerId: containerId,
            loggedAt: Date()
        )
        do {
            try await upsertLog(log)
        } catch {
            guard OfflineError.isConnectivity(error) else { throw error }
            OfflineOutbox.shared.enqueue(.addWater(log))
        }
        return log
    }

    /// Sends one log to the server - safe to repeat (same id, same row).
    func upsertLog(_ log: WaterLog) async throws {
        let userId = try await client.auth.session.user.id
        try await client
            .from("water_logs")
            .upsert(
                UpsertLog(
                    id: log.id,
                    user_id: userId,
                    date: log.date,
                    amount_ml: log.amountMl,
                    container_id: log.containerId,
                    logged_at: log.loggedAt
                ),
                onConflict: "id"
            )
            .execute()
    }

    func deleteLog(id: UUID) async throws {
        // Never reached the server: just forget it.
        if OfflineOutbox.shared.cancelPendingAddWater(id: id) { return }
        do {
            try await deleteLogOnServer(id: id)
        } catch {
            guard OfflineError.isConnectivity(error) else { throw error }
            OfflineOutbox.shared.enqueue(.deleteWater(id))
        }
    }

    func deleteLogOnServer(id: UUID) async throws {
        try await client
            .from("water_logs")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}
