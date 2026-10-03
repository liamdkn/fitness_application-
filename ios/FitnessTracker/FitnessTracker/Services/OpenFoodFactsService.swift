import Foundation

/// Free, no-API-key barcode lookup - the fallback when a scanned barcode
/// misses the local `foods` catalog. Per-100g/100ml figures only (Open
/// Food Facts doesn't reliably expose a per-serving breakdown across
/// products), so a hit is always inserted with a 100-unit serving regardless
/// of the product's own pack size - simplest, and the app already lets any
/// quantity multiplier scale it from there. The unit is ml for liquids
/// (milk, juice, oil - see `isLiquid`) and g for everything else.
enum OpenFoodFactsService {
    struct Lookup {
        let name: String
        let brand: String?
        let calories: Double
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
        let fiberG: Double?
        let sodiumMg: Double?
        let caffeineMg: Double?
        let isLiquid: Bool

        /// What the per-100 figures are per - measured out in ml, not g.
        var servingUnit: String { isLiquid ? "ml" : "g" }
    }

    /// Open Food Facts has no "this is a liquid" flag, so infer it from the
    /// pack size when there is one ("1 l", "500ml", "2 pints") and from its
    /// categories when there isn't (a milk with a blank quantity still sits
    /// under beverages/milks).
    static func isLiquid(quantity: String?, categories: [String]?) -> Bool {
        if let quantity,
           quantity.range(of: #"\d\s*(ml|cl|dl|l|ltr|litres?|liters?|fl\.?\s*oz|pints?)\b"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return true
        }
        let liquidCategories: Set<String> = ["en:beverages", "en:milks", "en:waters"]
        return categories?.contains(where: { liquidCategories.contains($0) }) ?? false
    }

    static func lookup(barcode: String) async throws -> Lookup? {
        guard let url = URL(
            string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=product_name,brands,nutriments,quantity,categories_tags"
        ) else { return nil }

        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let product = decoded.product,
              let name = product.productName, !name.isEmpty,
              let calories = product.nutriments?.energyKcal100g
        else { return nil }

        return Lookup(
            name: name,
            brand: primaryBrand(product.brands),
            calories: calories,
            proteinG: product.nutriments?.proteins100g ?? 0,
            carbsG: product.nutriments?.carbohydrates100g ?? 0,
            fatG: product.nutriments?.fat100g ?? 0,
            fiberG: product.nutriments?.fiber100g,
            sodiumMg: product.nutriments?.sodiumMg,
            caffeineMg: product.nutriments?.caffeineMg,
            isLiquid: isLiquid(quantity: product.quantity, categories: product.categoriesTags)
        )
    }

    /// OFF's `brands` is a comma-separated list ("Quaker,PepsiCo") - the
    /// first is the one on the front of the pack. `nil` when missing/blank,
    /// which the scan-confirm screen then asks the user to fill in.
    /// One text-search result - the product's barcode plus the same per-100g
    /// figures a barcode lookup returns, so picking it goes down the same
    /// cache-then-insert path (`FoodRepository.food(for:)`).
    struct SearchHit: Identifiable {
        let barcode: String
        let lookup: Lookup
        var id: String { barcode }
    }

    /// Text search via Open Food Facts' search service (free, no key; strong
    /// on UK/Irish own-brand grocery lines). Products with no calorie figure
    /// are dropped - a row that can't be logged is just noise - so many
    /// spices etc. won't appear; those can still be scanned or typed in.
    static func search(query: String, limit: Int = 25) async throws -> [SearchHit] {
        var components = URLComponents(string: "https://search.openfoodfacts.org/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page_size", value: String(limit)),
            URLQueryItem(name: "fields", value: "code,product_name,brands,nutriments,quantity,categories_tags"),
        ]
        guard let url = components?.url else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8

        let (data, _) = try await URLSession.shared.data(for: request)
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        let hits: [SearchHit] = decoded.hits.compactMap { hit in
            guard let code = hit.code, !code.isEmpty,
                  let name = hit.productName?.trimmingCharacters(in: .whitespaces), !name.isEmpty,
                  let calories = hit.nutriments?.energyKcal100g
            else { return nil }
            return SearchHit(
                barcode: code,
                lookup: Lookup(
                    name: name,
                    brand: primaryBrand(hit.brandList.first),
                    calories: calories,
                    proteinG: hit.nutriments?.proteins100g ?? 0,
                    carbsG: hit.nutriments?.carbohydrates100g ?? 0,
                    fatG: hit.nutriments?.fat100g ?? 0,
                    fiberG: hit.nutriments?.fiber100g,
                    sodiumMg: hit.nutriments?.sodiumMg,
                    caffeineMg: hit.nutriments?.caffeineMg,
                    isLiquid: isLiquid(quantity: hit.quantity, categories: hit.categoriesTags)
                )
            )
        }
        // Zero-calorie entries stay (diet drinks, water are genuinely 0) but
        // go last - plain spices etc. often carry a bogus 0 from missing data.
        return hits.filter { $0.lookup.calories > 0 } + hits.filter { $0.lookup.calories <= 0 }
    }

    private struct SearchResponse: Decodable {
        let hits: [SearchProduct]
    }

    private struct SearchProduct: Decodable {
        let code: String?
        let productName: String?
        let brandList: [String]
        let nutriments: Nutriments?
        let quantity: String?
        let categoriesTags: [String]?

        enum CodingKeys: String, CodingKey {
            case code, nutriments, brands, quantity
            case productName = "product_name"
            case categoriesTags = "categories_tags"
        }

        /// `brands` arrives as a list here (a plain string on the barcode
        /// endpoint) and as null for unbranded produce - accept either shape.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try? c.decodeIfPresent(String.self, forKey: .code)
            productName = try? c.decodeIfPresent(String.self, forKey: .productName)
            nutriments = try? c.decodeIfPresent(Nutriments.self, forKey: .nutriments)
            quantity = try? c.decodeIfPresent(String.self, forKey: .quantity)
            categoriesTags = try? c.decodeIfPresent([String].self, forKey: .categoriesTags)
            if let list = try? c.decodeIfPresent([String].self, forKey: .brands) {
                brandList = list
            } else if let single = try? c.decodeIfPresent(String.self, forKey: .brands) {
                brandList = [single]
            } else {
                brandList = []
            }
        }
    }

    private static func primaryBrand(_ brands: String?) -> String? {
        guard let first = brands?.split(separator: ",").first else { return nil }
        let trimmed = first.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private struct Response: Decodable {
        let product: Product?
    }

    private struct Product: Decodable {
        let productName: String?
        let brands: String?
        let nutriments: Nutriments?
        let quantity: String?
        let categoriesTags: [String]?

        enum CodingKeys: String, CodingKey {
            case productName = "product_name"
            case brands, nutriments, quantity
            case categoriesTags = "categories_tags"
        }
    }

    private struct Nutriments: Decodable {
        let energyKcal100g: Double?
        let proteins100g: Double?
        let carbohydrates100g: Double?
        let fat100g: Double?
        let fiber100g: Double?
        let sodium100g: Double?
        let salt100g: Double?
        let caffeine100g: Double?

        /// Caffeine in mg per 100 - OFF reports grams, like sodium.
        var caffeineMg: Double? {
            caffeine100g.map { ($0 * 1000 * 100).rounded() / 100 }
        }

        /// Sodium in mg per 100 - OFF reports grams, and many products give
        /// only salt (sodium = salt / 2.5), so fall back to that.
        var sodiumMg: Double? {
            if let sodium100g { return (sodium100g * 1000 * 100).rounded() / 100 }
            if let salt100g { return (salt100g * 400 * 100).rounded() / 100 }
            return nil
        }

        /// One odd-typed field shouldn't discard the whole product - each
        /// value decodes on its own and falls back to nil.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            energyKcal100g = try? c.decodeIfPresent(Double.self, forKey: .energyKcal100g)
            proteins100g = try? c.decodeIfPresent(Double.self, forKey: .proteins100g)
            carbohydrates100g = try? c.decodeIfPresent(Double.self, forKey: .carbohydrates100g)
            fat100g = try? c.decodeIfPresent(Double.self, forKey: .fat100g)
            fiber100g = try? c.decodeIfPresent(Double.self, forKey: .fiber100g)
            sodium100g = try? c.decodeIfPresent(Double.self, forKey: .sodium100g)
            salt100g = try? c.decodeIfPresent(Double.self, forKey: .salt100g)
            caffeine100g = try? c.decodeIfPresent(Double.self, forKey: .caffeine100g)
        }

        enum CodingKeys: String, CodingKey {
            case energyKcal100g = "energy-kcal_100g"
            case proteins100g = "proteins_100g"
            case carbohydrates100g = "carbohydrates_100g"
            case fat100g = "fat_100g"
            case fiber100g = "fiber_100g"
            case sodium100g = "sodium_100g"
            case salt100g = "salt_100g"
            case caffeine100g = "caffeine_100g"
        }
    }
}
