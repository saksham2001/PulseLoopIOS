import Foundation

// MARK: - Travel search configuration (Travel+ T8)

/// Reads travel-API credentials from Info.plist and gates usage behind a real
/// (non-placeholder) value, mirroring `WearableOAuthConfig.isConfigured`.
///
/// Keys (add real values to Info.plist; placeholders are treated as "not configured"):
///   - `AMADEUS_CLIENT_ID`     — Amadeus Self-Service API key
///   - `AMADEUS_CLIENT_SECRET` — Amadeus Self-Service API secret
enum TravelSearchConfig {
    enum Provider: String {
        case amadeus
    }

    static func value(_ key: String) -> String {
        let raw = (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A credential counts as "set" only when it isn't empty or a placeholder.
    static func isPlaceholder(_ value: String) -> Bool {
        value.isEmpty
            || value.hasPrefix("YOUR_")
            || value.hasPrefix("REPLACE")
            || value == "REPLACE_ME"
    }

    static var amadeusClientID: String { value("AMADEUS_CLIENT_ID") }
    static var amadeusClientSecret: String { value("AMADEUS_CLIENT_SECRET") }

    /// True when both Amadeus credentials are real values.
    static var isAmadeusConfigured: Bool {
        !isPlaceholder(amadeusClientID) && !isPlaceholder(amadeusClientSecret)
    }

    // MARK: Points / rewards valuation (T9)

    /// Base URL + API key for a points-valuation service (cents-per-point + transfer
    /// partners). Optional — when unset, the app falls back to built-in default cpp.
    static var pointsValuationBaseURL: String { value("POINTS_VALUATION_BASE_URL") }
    static var pointsValuationAPIKey: String { value("POINTS_VALUATION_API_KEY") }

    static var isPointsValuationConfigured: Bool {
        !isPlaceholder(pointsValuationBaseURL) && !isPlaceholder(pointsValuationAPIKey)
    }

    // MARK: Web search (Assistant+ T1)

    /// Provider-agnostic web search. `WEB_SEARCH_API_KEY` is the subscription token
    /// for the chosen search API (default provider: Brave Search). Optional — when
    /// unset, the `search_web` tool reports `configured:false` and the assistant
    /// stays honest instead of hallucinating live facts.
    static var webSearchAPIKey: String { value("WEB_SEARCH_API_KEY") }

    static var isWebSearchConfigured: Bool {
        !isPlaceholder(webSearchAPIKey)
    }

    // MARK: Community module gallery (Life OS T3)

    /// Base URL + optional API key for the community module gallery backend. When
    /// unset, the app serves a bundled, curated catalog so browse/search/install is
    /// always exercisable offline.
    static var moduleGalleryBaseURL: String { value("MODULE_GALLERY_BASE_URL") }
    static var moduleGalleryAPIKey: String { value("MODULE_GALLERY_API_KEY") }

    static var isModuleGalleryConfigured: Bool {
        !isPlaceholder(moduleGalleryBaseURL)
    }

    // MARK: Model catalog refresh (Life OS T4)

    /// Endpoint that lists available models + capabilities (e.g. OpenRouter
    /// `https://openrouter.ai/api/v1/models`). Optional — when unset, the app uses
    /// its bundled capability table.
    static var modelCatalogBaseURL: String { value("MODEL_CATALOG_BASE_URL") }

    static var isModelCatalogConfigured: Bool {
        !isPlaceholder(modelCatalogBaseURL)
    }
}
