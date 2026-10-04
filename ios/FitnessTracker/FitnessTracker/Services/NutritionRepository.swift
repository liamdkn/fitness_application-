import Foundation
import Supabase

/// Daily calories and macros. New days come from the in-app meal log; the
/// `nutrition_logs` table is only history - rows synced in from Apple Health
/// (MyFitnessPal) before the app had its own meal log - so readers get the
/// meal log first and fall back to those old rows for days that predate it.
struct NutritionRepository {
    let client = SupabaseService.shared.client

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
        // Old Apple Health history is a bonus: offline it's simply absent. The
        // meal log is read local-first, so entries logged with no signal count.
        async let healthResult = try? fetchRange(from: from, to: to)
        async let entriesResult = OfflineMealQueue.shared.fetchEntries(from: from, to: to)
        let health = await healthResult ?? []
        let entries = try await entriesResult
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
}
