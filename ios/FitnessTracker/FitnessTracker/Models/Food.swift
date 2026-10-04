import Foundation

/// What a food mainly is in a meal: a protein, carb or fat source, or
/// something else (seasoning, mostly-water foods). Lets a meal be read - and
/// later built - as its protein / carb / fat parts.
nonisolated enum FoodCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case protein, carb, fat, other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .protein: "Protein"
        case .carb: "Carbs"
        case .fat: "Fat"
        case .other: "Other"
        }
    }

    /// Order a meal lists its parts in.
    var sortOrder: Int {
        switch self {
        case .protein: 0
        case .carb: 1
        case .fat: 2
        case .other: 3
        }
    }

    /// Every role a food's numbers point to: each macro that supplies at least
    /// 30% of its energy (4/4/9 kcal per gram) - so salmon and eggs are both
    /// protein and fat sources. Empty for near-zero-calorie foods. The same
    /// rule the database backfill used, in display order.
    static func suggested(calories: Double, proteinG: Double, carbsG: Double, fatG: Double) -> [FoodCategory] {
        let p = proteinG * 4, c = carbsG * 4, f = fatG * 9
        let total = p + c + f
        guard total > 10 else { return [] }
        var result: [FoodCategory] = []
        if p / total >= 0.30 { result.append(.protein) }
        if c / total >= 0.30 { result.append(.carb) }
        if f / total >= 0.30 { result.append(.fat) }
        return result
    }
}

struct Food: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let brand: String?
    let servingSize: Double
    let servingUnit: String
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let fiberG: Double?
    let barcode: String?
    let source: String
    let isCustom: Bool
    let createdBy: UUID?
    /// Set once the user has checked this food against its pack and ticked
    /// "verified" - until then, picking or scanning it opens the full-screen
    /// check first (see `FoodPickerView`). A shared row (seed / Open Food
    /// Facts) is never verified in place; verifying it makes the user's own
    /// copy, which is.
    let isVerified: Bool
    /// Sodium per serving, in mg. `nil` = not recorded yet (distinct from 0).
    let sodiumMg: Double?
    /// Caffeine per serving, in mg. `nil` = not recorded (distinct from 0).
    let caffeineMg: Double?
    /// The shared catalog row this is a personal copy of, if any - used to
    /// hide the original from search once a copy exists.
    let sourceFoodId: UUID?
    /// Whether this belongs in Liquids and counts toward hydration and
    /// caffeine. Not the same as being measured in ml - olive oil and hot
    /// sauce are.
    let isDrink: Bool
    /// The roles this food fills in a meal (see `FoodCategory`) - empty when
    /// not set. A food can have several: salmon is a protein and a fat source.
    let categories: [FoodCategory]

    enum CodingKeys: String, CodingKey {
        case id, name, brand, categories
        case isDrink = "is_drink"
        case servingSize = "serving_size"
        case servingUnit = "serving_unit"
        case calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case fiberG = "fiber_g"
        case barcode, source
        case isCustom = "is_custom"
        case createdBy = "created_by"
        case isVerified = "is_verified"
        case sodiumMg = "sodium_mg"
        case caffeineMg = "caffeine_mg"
        case sourceFoodId = "source_food_id"
    }

    /// A food logged at `quantity` servings - `quantity` is a multiplier on
    /// this food's own serving (e.g. 1.5 servings of a 100g-serving food),
    /// not an absolute gram amount.
    func calories(at quantity: Double) -> Double { calories * quantity }
    func proteinG(at quantity: Double) -> Double { proteinG * quantity }
    func carbsG(at quantity: Double) -> Double { carbsG * quantity }
    func fatG(at quantity: Double) -> Double { fatG * quantity }
    func fiberG(at quantity: Double) -> Double? { fiberG.map { $0 * quantity } }
    func sodiumMg(at quantity: Double) -> Double? { sodiumMg.map { $0 * quantity } }
    func caffeineMg(at quantity: Double) -> Double? { caffeineMg.map { $0 * quantity } }

    /// The one a meal lists this food under: protein before carb before fat.
    var primaryCategory: FoodCategory? { categories.first }

    /// Source value of a one-off "just these calories and macros" entry.
    static let quickAddSource = "quick_add"

    /// True for a Quick Add entry - a hidden one-off that totals like any
    /// food but is never listed in search, recents or the food database.
    var isQuickAdd: Bool { source == Self.quickAddSource }

    /// A drink (`isDrink`) is measured in millilitres ("ml", or "ml cup" for a
    /// stored cup size) - logging one is a normal meal entry, and the Liquids
    /// screen reads hydration and caffeine from those entries. Foods saved
    /// before the flag existed decode as drinks if they're in ml.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        brand = try c.decodeIfPresent(String.self, forKey: .brand)
        servingSize = try c.decode(Double.self, forKey: .servingSize)
        servingUnit = try c.decode(String.self, forKey: .servingUnit)
        calories = try c.decode(Double.self, forKey: .calories)
        proteinG = try c.decode(Double.self, forKey: .proteinG)
        carbsG = try c.decode(Double.self, forKey: .carbsG)
        fatG = try c.decode(Double.self, forKey: .fatG)
        fiberG = try c.decodeIfPresent(Double.self, forKey: .fiberG)
        barcode = try c.decodeIfPresent(String.self, forKey: .barcode)
        source = try c.decode(String.self, forKey: .source)
        isCustom = try c.decode(Bool.self, forKey: .isCustom)
        createdBy = try c.decodeIfPresent(UUID.self, forKey: .createdBy)
        isVerified = try c.decode(Bool.self, forKey: .isVerified)
        sodiumMg = try c.decodeIfPresent(Double.self, forKey: .sodiumMg)
        caffeineMg = try c.decodeIfPresent(Double.self, forKey: .caffeineMg)
        sourceFoodId = try c.decodeIfPresent(UUID.self, forKey: .sourceFoodId)
        isDrink = try c.decodeIfPresent(Bool.self, forKey: .isDrink) ?? servingUnit.lowercased().hasPrefix("ml")
        categories = (try c.decodeIfPresent([FoodCategory].self, forKey: .categories) ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Millilitres in `quantity` servings; `nil` for a food that isn't a drink.
    func volumeMl(at quantity: Double) -> Double? { isDrink ? servingSize * quantity : nil }

    var servingLabel: String {
        let sizeText = servingSize == servingSize.rounded() ? String(Int(servingSize)) : String(format: "%.1f", servingSize)
        return "\(sizeText)\(servingUnit)"
    }

    var displayName: String {
        guard let brand, !brand.isEmpty else { return name }
        return "\(name) (\(brand))"
    }
}

/// How a logged quantity reads on a row: the real amount when the food is
/// measured out ("80g", "250ml"), a count for single items ("2 egg"), and
/// "1.5 x 182g medium" only for the unit-with-a-size kinds in between. The
/// stored `quantity` is a servings multiplier, so "0.8 x 100g" is what the
/// raw numbers say - this turns it into what was actually eaten.
enum AmountLabel {
    static func text(quantity: Double, servingSize: Double, servingUnit: String, servingLabel: String) -> String {
        let unit = servingUnit.lowercased()
        if unit == "g" || unit == "ml" {
            return trimmed(quantity * servingSize) + servingUnit
        }
        if servingSize == 1 {
            return "\(trimmed(quantity)) \(servingUnit)"
        }
        return "\(trimmed(quantity)) \u{00d7} \(servingLabel)"
    }

    /// One decimal at most, no trailing ".0" ("80", "37.5") - also absorbs
    /// float noise like 0.1 x 100 = 10.000000000000002.
    static func trimmed(_ value: Double) -> String {
        let text = String(format: "%.1f", value)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }
}

extension Food {
    func amountLabel(at quantity: Double) -> String {
        AmountLabel.text(quantity: quantity, servingSize: servingSize, servingUnit: servingUnit, servingLabel: servingLabel)
    }
}
