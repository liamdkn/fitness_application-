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
        let barcode: String?
        let source: String
        let is_custom: Bool
        let created_by: UUID
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
        let barcode: String
        let source: String
        let is_custom: Bool
    }

    /// Matches on name or brand - the `foods_name_trgm_idx` GIN index keeps
    /// a leading-wildcard `ilike` fast even as the catalog grows well past
    /// the seed set once Open Food Facts lookups start adding rows.
    func search(query: String, limit: Int = 30) async throws -> [Food] {
        // Strips characters that would break the raw `.or(...)` filter
        // syntax (a comma would split it into extra clauses, parens would
        // unbalance it) - harmless to drop from a plain text search term.
        let sanitized = query
            .trimmingCharacters(in: .whitespaces)
            .filter { !",()".contains($0) }
        guard !sanitized.isEmpty else { return [] }
        let pattern = "%\(sanitized)%"
        return try await client
            .from("foods")
            .select()
            .or("name.ilike.\(pattern),brand.ilike.\(pattern)")
            .order("name")
            .limit(limit)
            .execute()
            .value
    }

    /// The cache-hit path for a scanned barcode - checked before ever
    /// calling out to Open Food Facts.
    func fetchByBarcode(_ barcode: String) async throws -> Food? {
        let matches: [Food] = try await client
            .from("foods")
            .select()
            .eq("barcode", value: barcode)
            .limit(1)
            .execute()
            .value
        return matches.first
    }

    @discardableResult
    func insertFromOpenFoodFacts(barcode: String, lookup: OpenFoodFactsService.Lookup) async throws -> Food {
        let inserted: [Food] = try await client
            .from("foods")
            .insert(NewOffFood(
                name: lookup.name,
                brand: lookup.brand,
                serving_size: 100,
                serving_unit: "g",
                calories: lookup.calories,
                protein_g: lookup.proteinG,
                carbs_g: lookup.carbsG,
                fat_g: lookup.fatG,
                fiber_g: lookup.fiberG,
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
                barcode: barcode,
                source: source,
                is_custom: true,
                created_by: userId
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
