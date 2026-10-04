import Foundation
import Supabase

struct SupplementRepository {
    let client = SupabaseService.shared.client

    /// Insert payload. The unit and reminder times go as plain values; the
    /// scoop size as an explicit null so clearing it works.
    private struct SupplementWrite: Encodable {
        let user_id: UUID
        let name: String
        let unit: String
        let amount_per_serving: Double
        let scoop_size_g: Double?
        let servings_per_day: Int
        let reminder_times: [Int]
        let is_active: Bool
        let sort_order: Int

        enum CodingKeys: String, CodingKey {
            case user_id, name, unit, amount_per_serving, scoop_size_g, servings_per_day, reminder_times, is_active, sort_order
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(user_id, forKey: .user_id)
            try c.encode(name, forKey: .name)
            try c.encode(unit, forKey: .unit)
            try c.encode(amount_per_serving, forKey: .amount_per_serving)
            try c.encode(scoop_size_g, forKey: .scoop_size_g)
            try c.encode(servings_per_day, forKey: .servings_per_day)
            try c.encode(reminder_times, forKey: .reminder_times)
            try c.encode(is_active, forKey: .is_active)
            try c.encode(sort_order, forKey: .sort_order)
        }
    }

    private struct OverrideWrite: Encodable {
        let user_id: UUID
        let supplement_id: UUID
        let date: String
        let servings_per_day: Int?
        let amount_per_serving: Double?

        enum CodingKeys: String, CodingKey { case user_id, supplement_id, date, servings_per_day, amount_per_serving }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(user_id, forKey: .user_id)
            try c.encode(supplement_id, forKey: .supplement_id)
            try c.encode(date, forKey: .date)
            try c.encode(servings_per_day, forKey: .servings_per_day)
            try c.encode(amount_per_serving, forKey: .amount_per_serving)
        }
    }

    private struct LogWrite: Encodable {
        let id: UUID
        let user_id: UUID
        let supplement_id: UUID
        let date: String
        let amount: Double
        let taken_at: Date
    }

    // MARK: Supplements

    /// All of them, in the user's order, remembered for offline use.
    func fetchAll() async throws -> [Supplement] {
        try await cachedRead(key: "supplements") {
            try await client
                .from("supplements")
                .select()
                .order("sort_order")
                .order("created_at")
                .execute()
                .value
        }
    }

    @discardableResult
    func save(_ supplement: Supplement?, name: String, unit: SupplementUnit, amountPerServing: Double,
              scoopSizeG: Double?, servingsPerDay: Int, reminderTimes: [Int], sortOrder: Int) async throws -> Supplement {
        let userId = try await client.auth.session.user.id
        let row = SupplementWrite(
            user_id: userId, name: name, unit: unit.rawValue, amount_per_serving: amountPerServing,
            scoop_size_g: unit == .scoop ? scoopSizeG : nil, servings_per_day: servingsPerDay,
            reminder_times: Array(Set(reminderTimes.map { min(max($0, 0), 1439) })).sorted(),
            is_active: supplement?.isActive ?? true, sort_order: sortOrder
        )
        let saved: [Supplement]
        if let supplement {
            saved = try await client.from("supplements").update(row).eq("id", value: supplement.id).select().execute().value
        } else {
            saved = try await client.from("supplements").insert(row).select().execute().value
        }
        guard let result = saved.first else { throw RepositoryError.insertFailed }
        return result
    }

    func delete(id: UUID) async throws {
        try await client.from("supplements").delete().eq("id", value: id).execute()
    }

    // MARK: Overrides

    func fetchOverrides(date: Date) async throws -> [SupplementOverride] {
        let dateString = DateFormatting.isoDate(date)
        return try await cachedRead(key: "supplement-overrides-\(dateString)") {
            try await client
                .from("supplement_overrides")
                .select()
                .eq("date", value: dateString)
                .execute()
                .value
        }
    }

    func setOverride(supplementId: UUID, date: Date, servingsPerDay: Int?, amountPerServing: Double?) async throws {
        let userId = try await client.auth.session.user.id
        try await client
            .from("supplement_overrides")
            .upsert(OverrideWrite(
                user_id: userId, supplement_id: supplementId, date: DateFormatting.isoDate(date),
                servings_per_day: servingsPerDay, amount_per_serving: amountPerServing
            ), onConflict: "supplement_id,date")
            .execute()
    }

    func clearOverride(supplementId: UUID, date: Date) async throws {
        try await client
            .from("supplement_overrides")
            .delete()
            .eq("supplement_id", value: supplementId)
            .eq("date", value: DateFormatting.isoDate(date))
            .execute()
    }

    // MARK: Logs

    /// The day's logs including any not yet sent (taken offline), without any
    /// whose deletion is still waiting.
    @MainActor
    func fetchLogs(date: Date) async throws -> [SupplementLog] {
        let dateString = DateFormatting.isoDate(date)
        let key = "supplement-logs-\(dateString)"
        do {
            let logs: [SupplementLog] = try await client
                .from("supplement_logs")
                .select()
                .eq("date", value: dateString)
                .order("taken_at")
                .execute()
                .value
            OfflineReferenceCache.save(logs, key: key)
            return OfflineOutbox.shared.applyingPendingSupplementLogs(to: logs, date: dateString)
        } catch {
            guard OfflineError.isConnectivity(error) else { throw error }
            return OfflineOutbox.shared.applyingPendingSupplementLogs(
                to: OfflineReferenceCache.load([SupplementLog].self, key: key) ?? [], date: dateString
            )
        }
    }

    /// Every log in a range - for history.
    func fetchLogs(from: Date, to: Date) async throws -> [SupplementLog] {
        try await client
            .from("supplement_logs")
            .select()
            .gte("date", value: DateFormatting.isoDate(from))
            .lte("date", value: DateFormatting.isoDate(to))
            .order("taken_at")
            .execute()
            .value
    }

    /// Records a dose with a client-made id; queued if there's no connection.
    @MainActor
    @discardableResult
    func take(supplementId: UUID, amount: Double, at: Date = Date()) async throws -> SupplementLog {
        let log = SupplementLog(
            id: UUID(), supplementId: supplementId, date: DateFormatting.isoDate(at), amount: amount, takenAt: at
        )
        do {
            try await upsertLog(log)
        } catch {
            guard OfflineError.isConnectivity(error) else { throw error }
            OfflineOutbox.shared.enqueue(.addSupplementLog(log))
        }
        return log
    }

    func upsertLog(_ log: SupplementLog) async throws {
        let userId = try await client.auth.session.user.id
        try await client
            .from("supplement_logs")
            .upsert(LogWrite(
                id: log.id, user_id: userId, supplement_id: log.supplementId,
                date: log.date, amount: log.amount, taken_at: log.takenAt
            ), onConflict: "id")
            .execute()
    }

    @MainActor
    func deleteLog(id: UUID) async throws {
        if OfflineOutbox.shared.cancelPendingSupplementLog(id: id) { return }
        do {
            try await deleteLogOnServer(id: id)
        } catch {
            guard OfflineError.isConnectivity(error) else { throw error }
            OfflineOutbox.shared.enqueue(.deleteSupplementLog(id))
        }
    }

    func deleteLogOnServer(id: UUID) async throws {
        try await client.from("supplement_logs").delete().eq("id", value: id).execute()
    }

    /// The whole day, supplements joined with their override and logs.
    @MainActor
    func day(date: Date) async throws -> [SupplementDay] {
        async let supplements = fetchAll()
        async let overrides = fetchOverrides(date: date)
        async let logs = fetchLogs(date: date)
        let (all, ov, taken) = try await (supplements, overrides, logs)
        return all.filter(\.isActive).map { supplement in
            SupplementDay(
                supplement: supplement,
                override: ov.first { $0.supplementId == supplement.id },
                logs: taken.filter { $0.supplementId == supplement.id }
            )
        }
    }
}
