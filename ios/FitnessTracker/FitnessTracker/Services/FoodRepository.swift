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
        let barcode: String?
        let source: String
        let is_custom: Bool
        let created_by: UUID
        let is_verified: Bool
        let source_food_id: UUID?
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
        let barcode: String
        let source: String
        let is_custom: Bool
    }

    /// Matches on name or brand, word by word: "pink lady apple" finds foods
    /// containing any of those words, best first - everything matching all
    /// three, then two, then just "apple" - rather than requiring the whole
    /// phrase to appear contiguously (which found nothing for a plain
    /// "Apple" row). The `foods_name_trgm_idx` GIN index keeps the
    /// leading-wildcard `ilike`s fast as the catalog grows.
    func search(query: String, limit: Int = 30) async throws -> [Food] {
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
        let matches: [Food] = try await client
            .from("foods")
            .select()
            .eq("barcode", value: barcode)
            .execute()
            .value
        return matches.first(where: \.isCustom) ?? matches.first
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
        let is_verified: Bool

        enum CodingKeys: String, CodingKey {
            case name, brand, serving_size, serving_unit, calories, protein_g, carbs_g, fat_g, fiber_g, sodium_mg, is_verified
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
            try c.encode(is_verified, forKey: .is_verified)
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
        isVerified: Bool
    ) async throws -> Food {
        let userId = try await client.auth.session.user.id
        guard food.isCustom, food.createdBy == userId else {
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
                isVerified: isVerified,
                sourceFoodId: food.isCustom ? food.sourceFoodId : food.id,
                barcode: food.barcode
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
                is_verified: isVerified
            ))
            .eq("id", value: food.id)
            .select()
            .execute()
            .value
        guard let result = updated.first else { throw RepositoryError.insertFailed }
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
                barcode: barcode,
                source: "off",
                is_custom: false
            ))
            .select()
            .execute()
            .value
        guard let food = inserted.first else {
            throw RepositoryError.insertFailed
        }
        return food
    }

    func fetchByIds(_ ids: [UUID]) async throws -> [Food] {
        guard !ids.isEmpty else { return [] }
        return try await client
            .from("foods")
            .select()
            .in("id", values: ids)
            .execute()
            .value
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
        isVerified: Bool = false,
        sourceFoodId: UUID? = nil,
        barcode: String? = nil,
        source: String = "user"
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
                barcode: barcode,
                source: source,
                is_custom: true,
                created_by: userId,
                is_verified: isVerified,
                source_food_id: sourceFoodId
            ))
            .select()
            .execute()
            .value
        guard let food = inserted.first else {
            throw RepositoryError.insertFailed
        }
        return food
    }
}
