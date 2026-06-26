import Foundation
import os

struct OpenFoodFactsProduct {
    let name: String
    let brand: String?
    let categories: [String]
    let ingredients: String?
    let nutriments: OFFNutriments?
    let imageURL: URL?
    let barcode: String?
}

struct OFFNutriments {
    let calories: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let fiber: Double?
    let sugar: Double?
    let sodium: Double?
}

enum OpenFoodFactsService {

    private static let baseURL = "https://world.openfoodfacts.org"
    private static let userAgent = "PulseLoop iOS App - contact@pulseloop.xyz"
    /// Product data changes slowly; cache for an hour.
    private static let cache = ResponseCache(ttl: 60 * 60)

    private static func fetch(_ url: URL) async -> Data? {
        let key = url.absoluteString
        if let cached = cache.value(for: key) { return cached }
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, _) = try await NetworkRetry.send(request, transport: URLSession.shared)
            cache.set(data, for: key)
            return data
        } catch {
            AppLog.network.error("OpenFoodFacts request failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // Search by product name text
    static func search(query: String) async -> [OpenFoodFactsProduct] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "\(baseURL)/cgi/search.pl?search_terms=\(encoded)&search_simple=1&action=process&json=1&page_size=5") else {
            return []
        }
        guard let data = await fetch(url) else { return [] }
        return parseSearchResponse(data)
    }

    // Lookup by barcode
    static func lookup(barcode: String) async -> OpenFoodFactsProduct? {
        guard let url = URL(string: "\(baseURL)/api/v2/product/\(barcode).json") else {
            return nil
        }
        guard let data = await fetch(url) else { return nil }
        return parseSingleProduct(data)
    }

    // MARK: - Parsing

    private static func parseSearchResponse(_ data: Data) -> [OpenFoodFactsProduct] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let products = json["products"] as? [[String: Any]] else {
            return []
        }
        return products.compactMap { parseProductDict($0) }
    }

    private static func parseSingleProduct(_ data: Data) -> OpenFoodFactsProduct? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let product = json["product"] as? [String: Any] else {
            return nil
        }
        return parseProductDict(product)
    }

    private static func parseProductDict(_ dict: [String: Any]) -> OpenFoodFactsProduct? {
        let name = dict["product_name"] as? String ?? dict["product_name_en"] as? String ?? ""
        guard !name.isEmpty else { return nil }

        let brand = dict["brands"] as? String
        let categoriesStr = dict["categories"] as? String ?? ""
        let categories = categoriesStr.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let ingredients = dict["ingredients_text"] as? String ?? dict["ingredients_text_en"] as? String

        var nutriments: OFFNutriments?
        if let n = dict["nutriments"] as? [String: Any] {
            nutriments = OFFNutriments(
                calories: n["energy-kcal_100g"] as? Double ?? n["energy-kcal"] as? Double,
                protein: n["proteins_100g"] as? Double ?? n["proteins"] as? Double,
                carbs: n["carbohydrates_100g"] as? Double ?? n["carbohydrates"] as? Double,
                fat: n["fat_100g"] as? Double ?? n["fat"] as? Double,
                fiber: n["fiber_100g"] as? Double ?? n["fiber"] as? Double,
                sugar: n["sugars_100g"] as? Double ?? n["sugars"] as? Double,
                sodium: n["sodium_100g"] as? Double ?? n["sodium"] as? Double
            )
        }

        let imageURLStr = dict["image_front_url"] as? String ?? dict["image_url"] as? String
        let imageURL = imageURLStr.flatMap { URL(string: $0) }
        let barcode = dict["code"] as? String

        return OpenFoodFactsProduct(
            name: name,
            brand: brand,
            categories: categories,
            ingredients: ingredients,
            nutriments: nutriments,
            imageURL: imageURL,
            barcode: barcode
        )
    }

    // MARK: - Supplement Detection

    static func isLikelySupplement(_ product: OpenFoodFactsProduct) -> Bool {
        let supplementKeywords = ["supplement", "vitamin", "mineral", "protein", "amino", "creatine", "omega", "fish oil", "probiotic", "collagen", "herb", "extract"]
        let combined = (product.name + " " + product.categories.joined(separator: " ") + " " + (product.ingredients ?? "")).lowercased()
        return supplementKeywords.contains(where: { combined.contains($0) })
    }

    static func toSupplementInfo(_ product: OpenFoodFactsProduct) -> SupplementInfo {
        let category = isLikelySupplement(product) ? "supplement" : "food"
        let emoji = isLikelySupplement(product) ? "💊" : "🍽️"

        let benefit: String
        if let ingredients = product.ingredients, !ingredients.isEmpty {
            let shortIngredients = ingredients.prefix(120)
            benefit = "Contains: \(shortIngredients)\(ingredients.count > 120 ? "…" : "")"
        } else if let n = product.nutriments {
            var parts: [String] = []
            if let cal = n.calories { parts.append("\(Int(cal)) kcal") }
            if let p = n.protein { parts.append("\(Int(p))g protein") }
            if let c = n.carbs { parts.append("\(Int(c))g carbs") }
            if let f = n.fat { parts.append("\(Int(f))g fat") }
            benefit = parts.isEmpty ? "Nutritional supplement" : "Per 100g: " + parts.joined(separator: " · ")
        } else {
            benefit = "Product found in Open Food Facts database"
        }

        let dose = product.nutriments?.calories.map { "\(Int($0)) kcal/serving" } ?? "See label"
        let brandInfo = product.brand.map { " by \($0)" } ?? ""

        return SupplementInfo(
            name: product.name,
            aliases: [product.name.lowercased()],
            category: category,
            defaultDose: dose,
            emoji: emoji,
            timing: "AM",
            benefit: benefit,
            mechanism: "Product\(brandInfo). \(product.categories.prefix(3).joined(separator: ", "))",
            bestTimeReason: "Follow label instructions for timing and dosage",
            stackNotes: product.ingredients ?? "Check label for full ingredient list",
            interactionNotes: "Check with your healthcare provider for interactions",
            pros: [],
            cons: []
        )
    }
}
