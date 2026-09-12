import Foundation

/// Free, no-API-key barcode lookup - the fallback when a scanned barcode
/// misses the local `foods` catalog. Per-100g/100ml figures only (Open
/// Food Facts doesn't reliably expose a per-serving breakdown across
/// products), so a hit is always inserted with a 100g serving regardless
/// of the product's own pack size - simplest, and the app already lets any
/// quantity multiplier scale it from there.
enum OpenFoodFactsService {
    struct Lookup {
        let name: String
        let brand: String?
        let calories: Double
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
        let fiberG: Double?
    }

    static func lookup(barcode: String) async throws -> Lookup? {
        guard let url = URL(
            string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=product_name,brands,nutriments"
        ) else { return nil }

        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let product = decoded.product,
              let name = product.productName, !name.isEmpty,
              let calories = product.nutriments?.energyKcal100g
        else { return nil }

        return Lookup(
            name: name,
            brand: product.brands,
            calories: calories,
            proteinG: product.nutriments?.proteins100g ?? 0,
            carbsG: product.nutriments?.carbohydrates100g ?? 0,
            fatG: product.nutriments?.fat100g ?? 0,
            fiberG: product.nutriments?.fiber100g
        )
    }

    private struct Response: Decodable {
        let product: Product?
    }

    private struct Product: Decodable {
        let productName: String?
        let brands: String?
        let nutriments: Nutriments?

        enum CodingKeys: String, CodingKey {
            case productName = "product_name"
            case brands, nutriments
        }
    }

    private struct Nutriments: Decodable {
        let energyKcal100g: Double?
        let proteins100g: Double?
        let carbohydrates100g: Double?
        let fat100g: Double?
        let fiber100g: Double?

        enum CodingKeys: String, CodingKey {
            case energyKcal100g = "energy-kcal_100g"
            case proteins100g = "proteins_100g"
            case carbohydrates100g = "carbohydrates_100g"
            case fat100g = "fat_100g"
            case fiber100g = "fiber_100g"
        }
    }
}
