import Foundation
import Supabase

struct FoodRepository {
    let client = SupabaseService.shared.client

    private struct NewCustomFood: Encodable {
        let name: String
        let brand: String?
        let serving_size: Double
        let serving_unit: String
        let calories: Double
        let protein_g: Double
        let carbs_g: Double
        let fat_g: Double
        let fiber_g: Double?
        let sodium_mg: Double?
        let caffeine_mg: Double?
        let barcode: String?
        let source: String
        let is_custom: Bool
        let created_by: UUID
        let is_verified: Bool
        let source_food_id: UUID?
        let is_drink: Bool
        let categories: [String]
    }

    /// A shared row from an Open Food Facts hit - unowned (`created_by` is
    /// nil), unlike a user's own custom food.
    private struct NewOffFood: Encodable {
        let name: String
        let brand: String?
        let serving_size: Double
        let serving_unit: String
        let calories: Double
        let protein_g: Double
        let carbs_g: Double
        let fat_g: Double
        let fiber_g: Double?
        let sodium_mg: Double?
        let caffeine_mg: Double?
        let barcode: String
        let source: String
        let is_custom: Bool
        let is_drink: Bool
        let categories: [String]
    }

    /// Matches on name or brand, word by word: "pink lady apple" finds foods
    /// containing any of those words, best first - everything matching all
    /// three, then two, then just "apple" - rather than requiring the whole
    /// phrase to appear contiguously (which found nothing for a plain
    /// "Apple" row). The `foods_name_trgm_idx` GIN index keeps the
    /// leading-wildcard `ilike`s fast as the catalog grows.
    private func searchOnline(query: String, limit: Int = 30) async throws -> [Food] {
        // Strips characters that would break the raw `.or(...)` filter
        // syntax (a comma would split it into extra clauses, parens would
        // unbalance it) - harmless to drop from a plain text search term.
        let words = query
            .filter { !",()%*".contains($0) }
            .split(separator: " ")
            .map { String($0).lowercased() }
            .filter { $0.count >= 2 }
        guard !words.isEmpty else { return [] }
        let clauses = words.flatMap { ["name.ilike.%\($0)%", "brand.ilike.%\($0)%"] }
        let candidates: [Food] = try await client
            .from("foods")
            .select()
            .or(clauses.joined(separator: ","))
            .limit(100)
            .execute()
            .value

        // A word counts when it starts a word of the name/brand ("app" ->
        // "Apple"), not when it's buried inside one ("apple" in "Pineapple").
        func matchCount(_ food: Food) -> Int {
            let foodWords = "\(food.name) \(food.brand ?? "")"
                .lowercased()
                .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            return words.filter { word in foodWords.contains { $0.hasPrefix(word) } }.count
        }
        // A shared food the user has made their own copy of (verified or
        // corrected) is listed once - as the copy.
        struct CopyRef: Decodable {
            let sourceFoodId: UUID?
            enum CodingKeys: String, CodingKey { case sourceFoodId = "source_food_id" }
        }
        let copies: [CopyRef] = (try? await client
            .from("foods")
            .select("source_food_id")
            .in("source_food_id", values: candidates.map(\.id))
            .execute()
            .value) ?? []
        let copiedOriginals = Set(copies.compactMap(\.sourceFoodId))

        return candidates
            .filter { matchCount($0) > 0 && !copiedOriginals.contains($0.id) }
            .sorted {
                let (a, b) = (matchCount($0), matchCount($1))
                if a != b { return a > b }
                if $0.name.count != $1.name.count { return $0.name.count < $1.name.count }
                return $0.name < $1.name
            }
            .prefix(limit)
            .map { $0 }
    }

    /// The whole catalogue (mine and shared) A-Z for the Food Database screen,
    /// or - with search text - the ranked matches. A shared food the user has
    /// made their own copy of is listed once, as the copy.
    private func browseOnline(query: String, limit: Int = 500) async throws -> [Food] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return try await search(query: trimmed, limit: limit) }

        struct CopyRef: Decodable {
            let sourceFoodId: UUID?
            enum CodingKeys: String, CodingKey { case sourceFoodId = "source_food_id" }
        }
        async let foodsResult: [Food] = client
            .from("foods")
            .select()
            .order("name")
            .limit(limit)
            .execute()
            .value
        async let copiesResult: [CopyRef] = client
            .from("foods")
            .select("source_food_id")
            .not("source_food_id", operator: .is, value: "null")
            .execute()
            .value
        let foods = try await foodsResult
        let copied = Set(((try? await copiesResult) ?? []).compactMap(\.sourceFoodId))
        return foods.filter { !copied.contains($0.id) }
    }

    /// The seeded "Salt" food (0.39 g of sodium per gram), for adding salt to a
    /// meal in grams. Reading it also keeps it on the phone for offline use.
    func saltFood() async -> Food? {
        let found = (try? await search(query: "salt", limit: 30)) ?? []
        return found.first { $0.name.caseInsensitiveCompare("Salt") == .orderedSame && $0.source == "seed" }
            ?? Caches.foods.all.first { $0.name.caseInsensitiveCompare("Salt") == .orderedSame && $0.source == "seed" }
    }

    // MARK: Offline-aware reads
    //
    // Every food that comes back from the server is also kept on the phone
    // (`Caches.foods`), and the reads below fall back to that copy when
    // there's no connection - so foods you've seen are still findable,
    // scannable and loggable offline.

    func search(query: String, limit: Int = 30) async throws -> [Food] {
        do {
            let results = try await searchOnline(query: query, limit: limit)
            Caches.foods.store(results)
            return results.filter { !$0.isQuickAdd }
        } catch {
            guard OfflineError.isConnectivity(error) else { throw error }
            return Caches.searchFoods(query: query, limit: limit)
        }
    }

    func browse(query: String, limit: Int = 500) async throws -> [Food] {
        do {
            let foods = try await browseOnline(query: query, limit: limit)
            Caches.foods.store(foods)
            return foods.filter { !$0.isQuickAdd }
        } catch {
            guard OfflineError.isConnectivity(error) else { throw error }
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? Caches.allFoodsSorted() : Caches.searchFoods(query: trimmed, limit: limit)
        }
    }

    /// The catalog row for an online search hit: the one already stored for
    /// that barcode if there is one (mine or shared), else a new shared row
    /// inserted now - so the second time anyone searches it, it's a local hit.
    func food(for hit: OpenFoodFactsService.SearchHit) async throws -> Food {
        if let existing = try await fetchByBarcode(hit.barcode) { return existing }
        return try await insertFromOpenFoodFacts(barcode: hit.barcode, lookup: hit.lookup)
    }

    /// The cache-hit path for a scanned barcode - checked before ever
    /// calling out to Open Food Facts. A user's own corrected copy (see
    /// `saveCorrection`) wins over the shared row: row-level security only
    /// shows this user their own custom foods, so any custom match is theirs.
    func fetchByBarcode(_ barcode: String) async throws -> Food? {
        do {
            let matches: [Food] = try await client
                .from("foods")
                .select()
                .eq("barcode", value: barcode)
                .execute()
                .value
            Caches.foods.store(matches)
            return matches.first(where: \.isCustom) ?? matches.first
        } catch {
            guard OfflineError.isConnectivity(error) else { throw error }
            let matches = Caches.foods.all.filter { $0.barcode == barcode }
            return matches.first(where: \.isCustom) ?? matches.first
        }
    }

    /// Every editable field of a food, sent in full - `brand`/`fiber_g` are
    /// encoded as explicit nulls (not skipped) so clearing one in the edit
    /// form actually clears it, the same manual-`encode(to:)` pattern used
    /// elsewhere for optional columns.
    private struct CustomFoodUpdate: Encodable {
        let name: String
        let brand: String?
        let serving_size: Double
        let serving_unit: String
        let calories: Double
        let protein_g: Double
        let carbs_g: Double
        let fat_g: Double
        let fiber_g: Double?
        let sodium_mg: Double?
        let caffeine_mg: Double?
        let is_verified: Bool
        let is_drink: Bool
        let categories: [String]

        enum CodingKeys: String, CodingKey {
            case name, brand, serving_size, serving_unit, calories, protein_g, carbs_g, fat_g, fiber_g, sodium_mg, caffeine_mg, is_verified, is_drink, categories
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(name, forKey: .name)
            try c.encode(brand, forKey: .brand)
            try c.encode(serving_size, forKey: .serving_size)
            try c.encode(serving_unit, forKey: .serving_unit)
            try c.encode(calories, forKey: .calories)
            try c.encode(protein_g, forKey: .protein_g)
            try c.encode(carbs_g, forKey: .carbs_g)
            try c.encode(fat_g, forKey: .fat_g)
            try c.encode(fiber_g, forKey: .fiber_g)
            try c.encode(sodium_mg, forKey: .sodium_mg)
            try c.encode(caffeine_mg, forKey: .caffeine_mg)
            try c.encode(is_verified, forKey: .is_verified)
            try c.encode(is_drink, forKey: .is_drink)
            try c.encode(categories, forKey: .categories)
        }
    }

    /// Saves a correction to a scanned food's name/brand/macros. Shared rows
    /// (Open Food Facts, seed) aren't anyone's to edit, so a correction is
    /// stored as the user's own copy carrying the same barcode - the next
    /// scan finds that copy first. A food that's already the user's own
    /// custom row is simply updated in place.
    func saveCorrection(
        of food: Food,
        name: String,
        brand: String?,
        servingSize: Double,
        servingUnit: String,
        calories: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        fiberG: Double?,
        sodiumMg: Double?,
        caffeineMg: Double? = nil,
        isVerified: Bool,
        isDrink: Bool? = nil,
        categories: [FoodCategory]? = nil
    ) async throws -> Food {
        let userId = try await client.auth.session.user.id
        let drink = isDrink ?? food.isDrink
        // Left to auto: work them out from the numbers as saved.
        let resolvedCategories = categories
            ?? FoodCategory.suggested(calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG)
        // Correcting a catalogue food makes a personal copy that keeps its
        // barcode - and there can only be one such copy per barcode. If an
        // earlier correction already made it, edit that one instead of
        // trying to create a second (which the database rejects).
        var target = food
        if !(food.isCustom && food.createdBy == userId), let barcode = food.barcode {
            let existing: [Food] = try await client
                .from("foods")
                .select()
                .eq("is_custom", value: true)
                .eq("created_by", value: userId)
                .eq("barcode", value: barcode)
                .limit(1)
                .execute()
                .value
            if let own = existing.first { target = own }
        }
        guard target.isCustom, target.createdBy == userId else {
            return try await createCustom(
                name: name,
                brand: brand,
                servingSize: servingSize,
                servingUnit: servingUnit,
                calories: calories,
                proteinG: proteinG,
                carbsG: carbsG,
                fatG: fatG,
                fiberG: fiberG,
                sodiumMg: sodiumMg,
                caffeineMg: caffeineMg,
                isVerified: isVerified,
                sourceFoodId: food.isCustom ? food.sourceFoodId : food.id,
                barcode: food.barcode,
                isDrink: drink,
                categories: resolvedCategories
            )
        }
        let updated: [Food] = try await client
            .from("foods")
            .update(CustomFoodUpdate(
                name: name,
                brand: brand,
                serving_size: servingSize,
                serving_unit: servingUnit,
                calories: calories,
                protein_g: proteinG,
                carbs_g: carbsG,
                fat_g: fatG,
                fiber_g: fiberG,
                sodium_mg: sodiumMg,
                caffeine_mg: caffeineMg,
                is_verified: isVerified,
                is_drink: drink,
                categories: resolvedCategories.map(\.rawValue)
            ))
            .eq("id", value: target.id)
            .select()
            .execute()
            .value
        guard let result = updated.first else { throw RepositoryError.insertFailed }
        Caches.foods.store([result])
        return result
    }

    @discardableResult
    func insertFromOpenFoodFacts(barcode: String, lookup: OpenFoodFactsService.Lookup) async throws -> Food {
        let inserted: [Food] = try await client
            .from("foods")
            .insert(NewOffFood(
                name: lookup.name,
                brand: lookup.brand,
                serving_size: 100,
                serving_unit: lookup.servingUnit,
                calories: lookup.calories,
                protein_g: lookup.proteinG,
                carbs_g: lookup.carbsG,
                fat_g: lookup.fatG,
                fiber_g: lookup.fiberG,
                sodium_mg: lookup.sodiumMg,
                caffeine_mg: lookup.caffeineMg,
                barcode: barcode,
                source: "off",
                is_custom: false,
                is_drink: lookup.isDrink,
                categories: FoodCategory.suggested(
                    calories: lookup.calories, proteinG: lookup.proteinG, carbsG: lookup.carbsG, fatG: lookup.fatG
                ).map(\.rawValue)
            ))
            .select()
            .execute()
            .value
        guard let food = inserted.first else {
            throw RepositoryError.insertFailed
        }
        Caches.foods.store([food])
        return food
    }

    /// The user's own drinks (custom foods measured in ml) - a brew pot, a
    /// pod coffee - offered for quick logging even before they've been logged.
    func fetchCustomDrinks() async throws -> [Food] {
        do {
            let drinks: [Food] = try await client
                .from("foods")
                .select()
                .eq("is_custom", value: true)
                .ilike("serving_unit", pattern: "ml%")
                .order("name")
                .execute()
                .value
            Caches.foods.store(drinks)
            return drinks
        } catch {
            guard OfflineError.isConnectivity(error) else { throw error }
            return Caches.foods.all.filter { $0.isCustom && $0.isDrink }.sorted { $0.name < $1.name }
        }
    }

    func fetchByIds(_ ids: [UUID]) async throws -> [Food] {
        guard !ids.isEmpty else { return [] }
        do {
            let foods: [Food] = try await client
                .from("foods")
                .select()
                .in("id", values: ids)
                .execute()
                .value
            Caches.foods.store(foods)
            return foods
        } catch {
            guard OfflineError.isConnectivity(error) else { throw error }
            return Caches.foods.items(ids: ids)
        }
    }

    /// `source`/`barcode` default to a plain manual add - `source: "ocr"`
    /// and a real `barcode` are passed when this came from
    /// `NutritionLabelScannerView` instead (see
    /// `docs/nutrition-label-scan-brief.md`), so the row still ends up
    /// `is_custom: true` (it's still one person's OCR read, not a
    /// professionally verified source) but is distinguishable from a
    /// typed-by-hand entry, and doubles as a barcode cache hit for next
    /// time if one was scanned.
    @discardableResult
    func createCustom(
        name: String,
        brand: String?,
        servingSize: Double,
        servingUnit: String,
        calories: Double,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        fiberG: Double?,
        sodiumMg: Double? = nil,
        caffeineMg: Double? = nil,
        isVerified: Bool = false,
        sourceFoodId: UUID? = nil,
        barcode: String? = nil,
        source: String = "user",
        isDrink: Bool = false,
        categories: [FoodCategory]? = nil
    ) async throws -> Food {
        let userId = try await client.auth.session.user.id
        let inserted: [Food] = try await client
            .from("foods")
            .insert(NewCustomFood(
                name: name,
                brand: brand,
                serving_size: servingSize,
                serving_unit: servingUnit,
                calories: calories,
                protein_g: proteinG,
                carbs_g: carbsG,
                fat_g: fatG,
                fiber_g: fiberG,
                sodium_mg: sodiumMg,
                caffeine_mg: caffeineMg,
                barcode: barcode,
                source: source,
                is_custom: true,
                created_by: userId,
                is_verified: isVerified,
                source_food_id: sourceFoodId,
                is_drink: isDrink,
                categories: (categories ?? FoodCategory.suggested(
                    calories: calories, proteinG: proteinG, carbsG: carbsG, fatG: fatG
                )).map(\.rawValue)
            ))
            .select()
            .execute()
            .value
        guard let food = inserted.first else {
            throw RepositoryError.insertFailed
        }
        Caches.foods.store([food])
        return food
    }
}
