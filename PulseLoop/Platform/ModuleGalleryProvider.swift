import Foundation

// MARK: - Community module gallery provider (Life OS T3)
//
// A network-backed source of shareable sub-apps that drops into the existing
// `SubAppRegistryService` seam (so `SubAppRegistryView` needs no churn). It pulls a
// JSON catalog over the testable `HTTPTransport`, verifies/validates every package
// exactly like a local install, and degrades to the bundled curated catalog when
// unconfigured or offline — the browse/install flow always works.
//
// Modules are DECLARATIVE specs, never code: installing one can never run arbitrary
// code (the trusted spec runtime interprets it), which the consent UI states.
//
// Backend contract (GET {base}/modules and GET {base}/modules?q=...):
//   { "modules": [ { "category": "Health", "rating": 4.7, "rating_count": 200,
//                    "install_count": 5000,
//                    "changelog": [ { "version": "1.0.0", "notes": ["..."], "date": "2026-06" } ],
//                    "package": { <SubAppPackage JSON> } }, ... ] }

struct HTTPModuleGalleryProvider: SubAppRegistryService {
    private let transport: HTTPTransport
    private let baseURL: String
    private let apiKey: String
    /// Offline / unconfigured fallback (same curated catalog the app ships).
    private let fallback: SubAppRegistryService

    init(
        transport: HTTPTransport = URLSession.shared,
        baseURL: String = TravelSearchConfig.moduleGalleryBaseURL,
        apiKey: String = TravelSearchConfig.moduleGalleryAPIKey,
        fallback: SubAppRegistryService = BundledSubAppRegistryService()
    ) {
        self.transport = transport
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.fallback = fallback
    }

    var isConfigured: Bool { !TravelSearchConfig.isPlaceholder(baseURL) }

    // MARK: Requests (exposed for testing)

    func catalogRequest(query: String?) -> URLRequest? {
        guard var comps = URLComponents(string: baseURL) else { return nil }
        comps.path = (comps.path.hasSuffix("/") ? String(comps.path.dropLast()) : comps.path) + "/modules"
        if let query, !query.trimmingCharacters(in: .whitespaces).isEmpty {
            comps.queryItems = [URLQueryItem(name: "q", value: query)]
        }
        guard let url = comps.url else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        if !TravelSearchConfig.isPlaceholder(apiKey) {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    // MARK: Parsing (pure, exposed for testing)

    /// Decode a catalog response into verified listings. Any module whose package
    /// fails signature verification or schema validation is dropped (never trusted),
    /// so a tampered or malformed entry can't reach the install flow.
    static func parseCatalog(_ data: Data) throws -> [RegistryListing] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modules = root["modules"] as? [[String: Any]] else {
            throw GalleryError.decoding
        }
        return modules.compactMap { entry -> RegistryListing? in
            guard let packageObj = entry["package"],
                  let packageData = try? JSONSerialization.data(withJSONObject: packageObj),
                  // Decode + verify signature + validate the spec (drops tampered).
                  let spec = try? SubAppPackager.importSpec(from: packageData),
                  let package = try? SubAppPackager.makePackage(for: spec) else {
                return nil
            }
            let changelog = (entry["changelog"] as? [[String: Any]] ?? []).compactMap { parseChangelog($0) }
            return RegistryListing(
                package: package,
                category: (entry["category"] as? String) ?? "Community",
                communityRating: doubleValue(entry["rating"]) ?? 0,
                communityRatingCount: intValue(entry["rating_count"]) ?? 0,
                installCount: intValue(entry["install_count"]) ?? 0,
                changelog: changelog
            )
        }
    }

    private static func parseChangelog(_ obj: [String: Any]) -> SubAppChangelogEntry? {
        guard let version = obj["version"] as? String else { return nil }
        let notes = (obj["notes"] as? [String]) ?? []
        return SubAppChangelogEntry(version, notes, date: obj["date"] as? String)
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        return nil
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let s = any as? String { return Int(s) }
        return nil
    }

    // MARK: SubAppRegistryService

    func featured() async throws -> [RegistryListing] { try await fetch(query: nil) }
    func search(_ query: String) async throws -> [RegistryListing] { try await fetch(query: query) }

    private func fetch(query: String?) async throws -> [RegistryListing] {
        guard isConfigured, let request = catalogRequest(query: query) else {
            return try await fallbackListings(query: query)
        }
        do {
            let (data, response) = try await NetworkRetry.send(request, transport: transport)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return try await fallbackListings(query: query)
            }
            let listings = try Self.parseCatalog(data)
            // An empty/garbage live response shouldn't blank the gallery.
            return listings.isEmpty ? try await fallbackListings(query: query) : listings
        } catch {
            // Never let the gallery hard-fail; serve the bundled catalog.
            return try await fallbackListings(query: query)
        }
    }

    private func fallbackListings(query: String?) async throws -> [RegistryListing] {
        if let query { return try await fallback.search(query) }
        return try await fallback.featured()
    }

    enum GalleryError: Error { case decoding }
}
