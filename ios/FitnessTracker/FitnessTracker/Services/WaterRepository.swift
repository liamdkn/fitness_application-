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

    private struct NewLog: Encodable {
        let user_id: UUID
        let date: String
        let amount_ml: Int
        let container_id: UUID?
    }

    func fetchContainers() async throws -> [WaterContainer] {
        try await client
            .from("water_containers")
            .select()
            .order("name")
            .execute()
            .value
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

    func fetchLogs(date: Date) async throws -> [WaterLog] {
        try await client
            .from("water_logs")
            .select()
            .eq("date", value: DateFormatting.isoDate(date))
            .order("logged_at")
            .execute()
            .value
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

    @discardableResult
    func addLog(date: Date, amountMl: Int, containerId: UUID?) async throws -> WaterLog {
        let userId = try await client.auth.session.user.id
        let inserted: [WaterLog] = try await client
            .from("water_logs")
            .insert(NewLog(user_id: userId, date: DateFormatting.isoDate(date), amount_ml: amountMl, container_id: containerId))
            .select()
            .execute()
            .value
        guard let log = inserted.first else {
            throw RepositoryError.insertFailed
        }
        return log
    }

    func deleteLog(id: UUID) async throws {
        try await client
            .from("water_logs")
            .delete()
            .eq("id", value: id)
            .execute()
    }
}
