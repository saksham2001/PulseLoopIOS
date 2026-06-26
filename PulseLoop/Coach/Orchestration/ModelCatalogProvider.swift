import Foundation

// MARK: - Model catalog refresh provider (Life OS T4)
//
// Refreshes the candidate-model capability table from a live source (OpenRouter's
// `/models` endpoint) over the testable `HTTPTransport`. The app ships a curated
// `ModelRegistry.bundled` table, so this is purely additive: when configured it can
// surface newly available models; when unconfigured or offline it no-ops and the
// bundled table stands. New models are conservatively defaulted (tools/JSON-reliable
// unknown ⇒ not assumed) so a refresh can never silently break the agent loop.

protocol ModelCatalogProvider: Sendable {
    /// Fetch the latest model capabilities. Returns `[]` when unconfigured so callers
    /// keep the bundled table.
    func refresh() async -> [ModelCapability]
}

struct OpenRouterModelCatalogProvider: ModelCatalogProvider {
    private let transport: HTTPTransport
    private let baseURL: String

    init(
        transport: HTTPTransport = URLSession.shared,
        baseURL: String = TravelSearchConfig.modelCatalogBaseURL
    ) {
        self.transport = transport
        self.baseURL = baseURL
    }

    var isConfigured: Bool { !TravelSearchConfig.isPlaceholder(baseURL) }

    func catalogRequest() -> URLRequest? {
        guard let url = URL(string: baseURL) else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        return req
    }

    /// Parse OpenRouter's `{ "data": [ { "id": "vendor/model", "name": ...,
    /// "architecture": { "input_modalities": ["text","image"] },
    /// "supported_parameters": ["tools", ...] } ] }`. Pure, exposed for tests.
    static func parse(_ data: Data) -> [ModelCapability] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = root["data"] as? [[String: Any]] else { return [] }
        return models.compactMap { entry -> ModelCapability? in
            guard let slug = entry["id"] as? String, !slug.isEmpty else { return nil }
            let name = (entry["name"] as? String) ?? ModelRegistry.displayName(for: slug)
            let params = (entry["supported_parameters"] as? [String]) ?? []
            let supportsTools = params.contains("tools") || params.contains("tool_choice")
            let modalities = ((entry["architecture"] as? [String: Any])?["input_modalities"] as? [String]) ?? []
            let supportsVision = modalities.contains("image")
            // Preserve a known-good JSON reliability flag from the bundled table when
            // available; otherwise assume reliable only if tools are supported (the
            // anchor coercion in routing still protects the generalist regardless).
            let jsonReliable = ModelRegistry.capability(for: slug)?.jsonReliable ?? supportsTools
            let known = ModelRegistry.capability(for: slug)
            return ModelCapability(
                slug: slug,
                displayName: name,
                supportsTools: supportsTools,
                supportsVision: supportsVision,
                jsonReliable: jsonReliable,
                quality: known?.quality ?? 70,
                costRank: known?.costRank ?? 50
            )
        }
    }

    func refresh() async -> [ModelCapability] {
        guard isConfigured, let request = catalogRequest() else { return [] }
        do {
            let (data, response) = try await NetworkRetry.send(request, transport: transport)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return [] }
            return Self.parse(data)
        } catch {
            return []
        }
    }
}
