import Foundation

struct NutritionLog: Codable, Identifiable {
    let id: UUID
    let date: String
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let source: String

    enum CodingKeys: String, CodingKey {
        case id, date, calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
        case source
    }
}
