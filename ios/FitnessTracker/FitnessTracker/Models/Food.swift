import Foundation

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
    let isVerified: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, brand
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
    }

    /// A food logged at `quantity` servings - `quantity` is a multiplier on
    /// this food's own serving (e.g. 1.5 servings of a 100g-serving food),
    /// not an absolute gram amount.
    func calories(at quantity: Double) -> Double { calories * quantity }
    func proteinG(at quantity: Double) -> Double { proteinG * quantity }
    func carbsG(at quantity: Double) -> Double { carbsG * quantity }
    func fatG(at quantity: Double) -> Double { fatG * quantity }
    func fiberG(at quantity: Double) -> Double? { fiberG.map { $0 * quantity } }

    var servingLabel: String {
        let sizeText = servingSize == servingSize.rounded() ? String(Int(servingSize)) : String(format: "%.1f", servingSize)
        return "\(sizeText)\(servingUnit)"
    }

    var displayName: String {
        guard let brand, !brand.isEmpty else { return name }
        return "\(name) (\(brand))"
    }
}
