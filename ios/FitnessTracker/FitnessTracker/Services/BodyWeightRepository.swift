import Foundation
import Supabase

struct BodyWeightRepository {
    let client = SupabaseService.shared.client

    private struct NewBodyWeightLog: Encodable {
        let user_id: UUID
        let weight_kg: Double
        let source: String
    }

    private struct ImportedBodyWeightLog: Encodable {
        let user_id: UUID
        let weight_kg: Double
        let source: String
        let logged_at: Date
    }

    /// Adds weigh-ins found in Apple Health that aren't logged yet - the scale
    /// writes to Health through its own app, and they land here as
    /// `healthkit` entries stamped with when the scale took them. A reading
    /// already present (any source) at the same weight within two minutes is
    /// the same weigh-in and is skipped, so syncing again never duplicates.
    /// Returns how many were added.
    @discardableResult
    func importHealthWeights(_ samples: [(date: Date, kg: Double)], daysBack: Int) async throws -> Int {
        guard !samples.isEmpty else { return 0 }
        let existing = try await fetchRecent(days: daysBack + 1)
        let userId = try await client.auth.session.user.id
        var added: [ImportedBodyWeightLog] = []
        for sample in samples where sample.kg > 20 && sample.kg < 400 {
            let alreadyThere = existing.contains {
                abs($0.loggedAt.timeIntervalSince(sample.date)) < 120 && abs($0.weightKg - sample.kg) < 0.05
            } || added.contains {
                abs($0.logged_at.timeIntervalSince(sample.date)) < 120 && abs($0.weight_kg - sample.kg) < 0.05
            }
            guard !alreadyThere else { continue }
            added.append(ImportedBodyWeightLog(user_id: userId, weight_kg: sample.kg, source: "healthkit", logged_at: sample.date))
        }
        guard !added.isEmpty else { return 0 }
        try await client.from("body_weight_logs").insert(added).execute()
        return added.count
    }

    func fetchRecent(days: Int) async throws -> [BodyWeightLog] {
        let calendar = Calendar.current
        let since = calendar.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return try await client
            .from("body_weight_logs")
            .select()
            .gte("logged_at", value: since.ISO8601Format())
            .order("logged_at")
            .execute()
            .value
    }

    /// Range-filtered, unlike `fetchRecent(days:)` which is always anchored
    /// to today - lets Weekly Insights show a past week's weigh-ins.
    func fetchRange(from: Date, to: Date) async throws -> [BodyWeightLog] {
        try await client
            .from("body_weight_logs")
            .select()
            .gte("logged_at", value: from.ISO8601Format())
            .lte("logged_at", value: to.ISO8601Format())
            .order("logged_at")
            .execute()
            .value
    }

    /// Most recent first - the weigh-in history list. Unlike
    /// `fetchRecent(days:)`/`fetchRange(from:to:)` (both oldest-first, for
    /// charts), a history list reads naturally newest-on-top.
    func fetchHistory(limit: Int = 200) async throws -> [BodyWeightLog] {
        try await client
            .from("body_weight_logs")
            .select()
            .order("logged_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    /// Latest logged weight, remembered for offline use - what per-kg targets
    /// (the preworkout carb goal) are worked out from.
    func latestWeightKg() async throws -> Double? {
        let cached: [Double] = try await cachedRead(key: "latest-weight-kg") {
            let rows: [BodyWeightLog] = try await client
                .from("body_weight_logs")
                .select()
                .order("logged_at", ascending: false)
                .limit(1)
                .execute()
                .value
            return rows.map(\.weightKg)
        }
        return cached.first
    }

    func deleteLog(id: UUID) async throws {
        try await client
            .from("body_weight_logs")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    private struct WeightUpdate: Encodable {
        let weight_kg: Double
    }

    /// Corrects today's already-logged weigh-in in place (e.g. re-opening
    /// the Daily Check-In after mistyping this morning's weight) instead of
    /// adding a second entry for the same day. Updates whichever log is
    /// most recent for today, regardless of source - a manual correction
    /// should win over a stale HealthKit sync too. Returns `nil` when
    /// nothing's logged yet today, so the caller knows to insert instead.
    @discardableResult
    func updateTodaysWeight(kg: Double) async throws -> BodyWeightLog? {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let todaysLogs: [BodyWeightLog] = try await client
            .from("body_weight_logs")
            .select()
            .gte("logged_at", value: startOfToday.ISO8601Format())
            .order("logged_at", ascending: false)
            .limit(1)
            .execute()
            .value
        guard let latest = todaysLogs.first else { return nil }
        let updated: [BodyWeightLog] = try await client
            .from("body_weight_logs")
            .update(WeightUpdate(weight_kg: kg))
            .eq("id", value: latest.id)
            .select()
            .execute()
            .value
        return updated.first
    }

    @discardableResult
    func logWeight(kg: Double) async throws -> BodyWeightLog {
        let userId = try await client.auth.session.user.id
        let inserted: [BodyWeightLog] = try await client
            .from("body_weight_logs")
            .insert(NewBodyWeightLog(user_id: userId, weight_kg: kg, source: "manual"))
            .select()
            .execute()
            .value
        guard let log = inserted.first else {
            throw RepositoryError.insertFailed
        }
        return log
    }
}
