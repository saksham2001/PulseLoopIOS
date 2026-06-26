import Foundation
import os

struct FDADrugResult {
    let brandName: String
    let genericName: String
    let purpose: String?
    let warnings: String?
    let dosageForm: String?
    let route: String?
    let activeIngredients: [String]
    let indications: String?
}

enum OpenFDAService {

    private static let baseURL = "https://api.fda.gov/drug"
    /// Drug labels change slowly; cache lookups for an hour to cut repeat calls.
    private static let cache = ResponseCache(ttl: 60 * 60)

    /// Fetch with retry + cache. Returns nil on failure (logged) so callers can
    /// distinguish "no data" from a thrown error if they care.
    private static func fetch(_ url: URL) async -> Data? {
        let key = url.absoluteString
        // Empty cached data is a cached "no matches" (404); return nil for it so a
        // cache hit behaves the same as the original miss instead of handing back
        // empty data that callers would try to decode.
        if let cached = cache.value(for: key) { return cached.isEmpty ? nil : cached }
        do {
            let (data, response) = try await NetworkRetry.send(URLRequest(url: url), transport: URLSession.shared)
            if let http = response as? HTTPURLResponse, http.statusCode == 404 {
                // openFDA returns 404 for "no matches" — a valid empty result, cache it.
                cache.set(Data(), for: key)
                return nil
            }
            cache.set(data, for: key)
            return data
        } catch {
            AppLog.network.error("openFDA request failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    // Search drug labels by name
    static func searchDrugs(query: String) async -> [FDADrugResult] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let searchField = "openfda.brand_name:\"\(encoded)\"+openfda.generic_name:\"\(encoded)\""
        guard let url = URL(string: "\(baseURL)/label.json?search=\(searchField)&limit=3") else {
            return []
        }
        guard let data = await fetch(url) else { return [] }
        return parseLabelResponse(data)
    }

    // Broader text search across drug labels
    static func searchLabels(query: String) async -> [FDADrugResult] {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        guard let url = URL(string: "\(baseURL)/label.json?search=\(encoded)&limit=5") else {
            return []
        }
        guard let data = await fetch(url) else { return [] }
        return parseLabelResponse(data)
    }

    // MARK: - Parsing

    private static func parseLabelResponse(_ data: Data) -> [FDADrugResult] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else {
            return []
        }
        return results.compactMap { parseDrugLabel($0) }
    }

    private static func parseDrugLabel(_ dict: [String: Any]) -> FDADrugResult? {
        let openfda = dict["openfda"] as? [String: Any] ?? [:]

        let brandNames = openfda["brand_name"] as? [String] ?? []
        let genericNames = openfda["generic_name"] as? [String] ?? []

        let brandName = brandNames.first ?? ""
        let genericName = genericNames.first ?? ""

        guard !brandName.isEmpty || !genericName.isEmpty else { return nil }

        let purpose = (dict["purpose"] as? [String])?.first
        let warnings = (dict["warnings"] as? [String])?.first
        let dosageForm = (openfda["dosage_form"] as? [String])?.first
        let route = (openfda["route"] as? [String])?.first
        let indications = (dict["indications_and_usage"] as? [String])?.first

        let activeIngredients: [String]
        if let substances = openfda["substance_name"] as? [String] {
            activeIngredients = substances
        } else {
            activeIngredients = []
        }

        return FDADrugResult(
            brandName: brandName,
            genericName: genericName,
            purpose: purpose,
            warnings: warnings,
            dosageForm: dosageForm,
            route: route,
            activeIngredients: activeIngredients,
            indications: indications
        )
    }

    // MARK: - Conversion

    static func toSupplementInfo(_ drug: FDADrugResult) -> SupplementInfo {
        let name = drug.brandName.isEmpty ? drug.genericName : drug.brandName
        let displayName = name.prefix(1).uppercased() + name.dropFirst().lowercased()

        let benefit: String
        if let indications = drug.indications, !indications.isEmpty {
            benefit = String(indications.prefix(200))
        } else if let purpose = drug.purpose, !purpose.isEmpty {
            benefit = purpose
        } else {
            benefit = "Medication found in FDA database"
        }

        let mechanism: String
        if !drug.activeIngredients.isEmpty {
            mechanism = "Active ingredients: " + drug.activeIngredients.prefix(5).joined(separator: ", ")
        } else if !drug.genericName.isEmpty {
            mechanism = "Generic: \(drug.genericName)"
        } else {
            mechanism = "Prescription/OTC medication"
        }

        let interactionNotes: String
        if let warnings = drug.warnings, !warnings.isEmpty {
            interactionNotes = String(warnings.prefix(200))
        } else {
            interactionNotes = "Consult your healthcare provider for interactions and contraindications"
        }

        let routeInfo = drug.route.map { "Route: \($0). " } ?? ""
        let formInfo = drug.dosageForm.map { "Form: \($0). " } ?? ""

        return SupplementInfo(
            name: displayName,
            aliases: [name.lowercased(), drug.genericName.lowercased()],
            category: "medication",
            defaultDose: "\(formInfo)See prescribing info",
            emoji: "💊",
            timing: "See label",
            benefit: benefit,
            mechanism: mechanism,
            bestTimeReason: "\(routeInfo)Follow your prescriber's instructions for timing and dosage",
            stackNotes: "Active: \(drug.activeIngredients.prefix(3).joined(separator: ", "))",
            interactionNotes: interactionNotes,
            pros: [],
            cons: []
        )
    }
}
