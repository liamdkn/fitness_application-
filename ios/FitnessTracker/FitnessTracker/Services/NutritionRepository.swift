import Foundation
import Supabase

struct NutritionRepository {
    let client = SupabaseService.shared.client

    private struct UpsertNutritionLog: Encodable {
        let user_id: UUID
        let date: String
        let calories: Double
        let protein_g: Double
        let carbs_g: Double
        let fat_g: Double
        let source: String
    }

    struct SyncedNutritionLog {
        let date: String
        let calories: Double
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
    }

    func fetchLog(date: Date) async throws -> NutritionLog? {
        let dateString = DateFormatting.isoDate(date)
        let logs: [NutritionLog] = try await client
            .from("nutrition_logs")
            .select()
            .eq("date", value: dateString)
            .limit(1)
            .execute()
            .value
        return logs.first
    }

    // MARK: - Daily totals (meal log first, Health as the fallback)

    /// One day's calories and macros as everything *except* the Nutrition
    /// tab should see them: the in-app meal log's total if that day has any
    /// entries, otherwise Apple Health's synced total (`nutrition_logs`).
    /// Without this, Weekly Insights, the TDEE estimate, the dashboard and
    /// the check-ins only ever read `nutrition_logs` - so food logged in the
    /// app never reached them. The Nutrition tab itself keeps using
    /// `fetchLog` directly, because it adds Health on top of the meal log
    /// while the two are being transitioned between.
    func fetchDailyTotal(date: Date) async throws -> NutritionLog? {
        try await fetchDailyTotals(from: date, to: date).first
    }

    func fetchDailyTotals(from: Date, to: Date) async throws -> [NutritionLog] {
        async let healthResult = fetchRange(from: from, to: to)
        async let entriesResult = MealEntryRepository().fetchEntries(from: from, to: to)
        let (health, entries) = try await (healthResult, entriesResult)
        guard !entries.isEmpty else { return health }

        let foodIds = Array(Set(entries.compactMap(\.foodId)))
        let recipeIds = Array(Set(entries.compactMap(\.recipeId)))
        let foods = Dictionary(uniqueKeysWithValues: try await Self.fetchInChunks(foodIds) { try await FoodRepository().fetchByIds($0) }.map { ($0.id, $0) })
        let recipes = Dictionary(uniqueKeysWithValues: try await Self.fetchInChunks(recipeIds) { try await RecipeRepository().fetchByIds($0) }.map { ($0.id, $0) })

        let mealTotals = Self.totalsByDate(entries: entries, foods: foods, recipes: recipes)
        var byDate = Dictionary(uniqueKeysWithValues: health.map { ($0.date, $0) })
        for (date, totals) in mealTotals {
            byDate[date] = NutritionLog(
                id: byDate[date]?.id ?? UUID(),
                date: date,
                calories: totals.calories,
                proteinG: totals.proteinG,
                carbsG: totals.carbsG,
                fatG: totals.fatG,
                source: "meal_log"
            )
        }
        return byDate.values.sorted { $0.date < $1.date }
    }

    /// Per-date calories and macros from logged entries: each entry's
    /// quantity times its food's or recipe's cached per-serving numbers.
    static func totalsByDate(entries: [MealEntry], foods: [UUID: Food], recipes: [UUID: Recipe]) -> [String: DayMacroTotals] {
        var totals: [String: DayMacroTotals] = [:]
        for entry in entries {
            var day = totals[entry.date] ?? DayMacroTotals()
            if let food = entry.foodId.flatMap({ foods[$0] }) {
                day.calories += food.calories(at: entry.quantity)
                day.proteinG += food.proteinG(at: entry.quantity)
                day.carbsG += food.carbsG(at: entry.quantity)
                day.fatG += food.fatG(at: entry.quantity)
            } else if let recipe = entry.recipeId.flatMap({ recipes[$0] }) {
                day.calories += recipe.calories(at: entry.quantity)
                day.proteinG += recipe.proteinG(at: entry.quantity)
                day.carbsG += recipe.carbsG(at: entry.quantity)
                day.fatG += recipe.fatG(at: entry.quantity)
            }
            totals[entry.date] = day
        }
        return totals
    }

    /// `IN (...)` lists go in the request URL, so a long history's worth of
    /// ids is fetched in batches rather than one enormous request.
    static func fetchInChunks<T>(_ ids: [UUID], _ fetch: ([UUID]) async throws -> [T]) async throws -> [T] {
        var result: [T] = []
        for start in stride(from: 0, to: ids.count, by: 80) {
            result += try await fetch(Array(ids[start..<min(start + 80, ids.count)]))
        }
        return result
    }

    func fetchRecent(days: Int) async throws -> [NutritionLog] {
        try await client
            .from("nutrition_logs")
            .select()
            .order("date", ascending: false)
            .limit(days)
            .execute()
            .value
    }

    /// All logged days within an inclusive calendar range (as opposed to
    /// `fetchRecent`'s row-count limit), used where the caller needs the
    /// window to line up with a date range from another source - e.g.
    /// matching the adaptive TDEE engine's weight-log window.
    func fetchRange(from: Date, to: Date) async throws -> [NutritionLog] {
        try await client
            .from("nutrition_logs")
            .select()
            .gte("date", value: DateFormatting.isoDate(from))
            .lte("date", value: DateFormatting.isoDate(to))
            .order("date")
            .execute()
            .value
    }

    @discardableResult
    func upsertLog(date: Date, calories: Double, proteinG: Double, carbsG: Double, fatG: Double) async throws -> NutritionLog {
        let userId = try await client.auth.session.user.id
        let payload = UpsertNutritionLog(
            user_id: userId,
            date: DateFormatting.isoDate(date),
            calories: calories,
            protein_g: proteinG,
            carbs_g: carbsG,
            fat_g: fatG,
            source: "manual"
        )
        let logs: [NutritionLog] = try await client
            .from("nutrition_logs")
            .upsert(payload, onConflict: "user_id,date")
            .select()
            .execute()
            .value
        guard let log = logs.first else {
            throw RepositoryError.insertFailed
        }
        return log
    }

    private struct DateOnlyRow: Decodable {
        let date: String
    }

    /// Batch upsert for the HealthKit sync path (mirrors
    /// `HealthRepository.upsertSteps`/`upsertSleep`). This user has no real
    /// HealthKit nutrition source - every "healthkit" row here is really a
    /// blank/zero reading, and a day already logged manually (typically
    /// pasted-in MFP totals via `upsertLog`, tagged `source: "manual"`)
    /// should stick rather than get silently blown away the next time this
    /// sync runs. So any date in this batch that's already manually logged
    /// is dropped from the payload before the upsert, leaving that row
    /// untouched; only genuinely un-logged days get the HealthKit value.
    func upsertLogs(_ logs: [SyncedNutritionLog]) async throws {
        guard !logs.isEmpty else { return }
        let userId = try await client.auth.session.user.id

        let candidateDates = logs.map(\.date)
        let manuallyLoggedDates: Set<String> = try await {
            let rows: [DateOnlyRow] = try await client
                .from("nutrition_logs")
                .select("date")
                .eq("source", value: "manual")
                .in("date", values: candidateDates)
                .execute()
                .value
            return Set(rows.map(\.date))
        }()

        let payload = logs
            .filter { !manuallyLoggedDates.contains($0.date) }
            .map {
                UpsertNutritionLog(
                    user_id: userId,
                    date: $0.date,
                    calories: $0.calories,
                    protein_g: $0.proteinG,
                    carbs_g: $0.carbsG,
                    fat_g: $0.fatG,
                    source: "healthkit"
                )
            }
        guard !payload.isEmpty else { return }
        try await client
            .from("nutrition_logs")
            .upsert(payload, onConflict: "user_id,date")
            .execute()
    }
}
