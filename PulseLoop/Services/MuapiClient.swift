import Foundation

// MARK: - MuapiClient (multifunction roadmap M2)
//
// Thin async/await client for muapi.ai's unified generative-media API. muapi uses a
// submit-then-poll pattern across every modality:
//   POST /api/v1/{model}                          -> { request_id }
//   GET  /api/v1/predictions/{request_id}/result  -> { status, outputs[] }
// Auth is an `x-api-key` header. The key is resolved from the Keychain (never source).
//
// Sandbox mode (`?sandbox=true`-style header `x-sandbox`) makes muapi return a model's
// example media for free, so first-run + tests never spend real credits.
//
// The client is transport-injectable (`MuapiTransport`) so tests can feed canned
// responses without hitting the network.

// MARK: Result + model types

/// Outcome of a generation job once polling reports `completed`.
struct MuapiResult: Equatable {
    let requestID: String
    let status: String
    /// Output media URLs (images or MP4s on muapi's CDN).
    let outputs: [URL]
    var isCompleted: Bool { status.lowercased() == "completed" }
}

/// One model in the muapi catalog (`GET /api/v1/models`).
struct MuapiModel: Codable, Equatable, Identifiable {
    let name: String
    let category: String?
    let description: String?
    /// Per-call USD cost when muapi reports it.
    let costUSD: Double?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case category
        case description
        case costUSD = "cost_usd"
    }
}

enum MuapiError: Error, LocalizedError {
    case missingAPIKey
    case http(Int, String)
    case decoding(String)
    case timedOut
    case cancelled
    case noOutputs

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "No muapi API key. Add one in Settings → AI Assistant."
        case let .http(code, body): return "muapi request failed (\(code)): \(body.prefix(160))"
        case let .decoding(msg): return "Couldn't read muapi response: \(msg)"
        case .timedOut: return "Generation timed out. Try again or pick a faster model."
        case .cancelled: return "Generation cancelled."
        case .noOutputs: return "muapi returned no media."
        }
    }
}

// MARK: Transport seam (for tests)

/// Minimal transport so `MuapiClient` can be unit-tested without the network.
protocol MuapiTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: MuapiTransport {
    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request, delegate: nil)
    }
}

// MARK: Client

struct MuapiClient {
    static let baseURL = URL(string: "https://api.muapi.ai/api/v1")!

    private let transport: MuapiTransport
    private let keyStore: APIKeyStore
    private let sandbox: Bool
    /// Poll cadence + ceiling. Image jobs finish in seconds; video can take minutes.
    private let pollInterval: TimeInterval
    private let pollTimeout: TimeInterval

    init(
        transport: MuapiTransport = URLSession.shared,
        keyStore: APIKeyStore = MuapiKeychainStore(),
        sandbox: Bool = false,
        pollInterval: TimeInterval = 2.0,
        pollTimeout: TimeInterval = 300.0
    ) {
        self.transport = transport
        self.keyStore = keyStore
        self.sandbox = sandbox
        self.pollInterval = pollInterval
        self.pollTimeout = pollTimeout
    }

    private func apiKey() throws -> String {
        guard let key = (try? keyStore.readKey()) ?? nil, !key.isEmpty else {
            throw MuapiError.missingAPIKey
        }
        return key
    }

    /// Send a request, retrying transient failures (network errors + 5xx + 429) with
    /// exponential backoff. Non-transient HTTP errors surface immediately.
    private func sendWithRetry(_ request: URLRequest, maxAttempts: Int = 3) async throws -> (Data, URLResponse) {
        var attempt = 0
        var delay: TimeInterval = 0.4
        while true {
            try Task.checkCancellation()
            attempt += 1
            do {
                let (data, response) = try await transport.data(for: request)
                if let http = response as? HTTPURLResponse,
                   (http.statusCode >= 500 || http.statusCode == 429),
                   attempt < maxAttempts {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    delay *= 2
                    continue
                }
                return (data, response)
            } catch is CancellationError {
                throw MuapiError.cancelled
            } catch {
                guard attempt < maxAttempts else { throw error }
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                delay *= 2
            }
        }
    }

    private func authorized(_ request: inout URLRequest) throws {
        request.setValue(try apiKey(), forHTTPHeaderField: "x-api-key")
        if sandbox { request.setValue("true", forHTTPHeaderField: "x-sandbox") }
    }

    // MARK: Submit + poll

    /// Submit a generation job. Returns the `request_id` to poll.
    func submit(model: String, params: [String: Any]) async throws -> String {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent(model))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try authorized(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: params, options: [])

        let (data, response) = try await sendWithRetry(request)
        try Self.checkHTTP(response, data)
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MuapiError.decoding("submit response was not a JSON object")
        }
        if let id = (obj["request_id"] ?? obj["id"]) as? String { return id }
        throw MuapiError.decoding("submit response missing request_id")
    }

    /// Poll the result endpoint until `completed` (or failure / timeout / cancel).
    func pollResult(requestID: String) async throws -> MuapiResult {
        let deadline = Date().addingTimeInterval(pollTimeout)
        let url = Self.baseURL
            .appendingPathComponent("predictions")
            .appendingPathComponent(requestID)
            .appendingPathComponent("result")

        while true {
            try Task.checkCancellation()
            if Date() > deadline { throw MuapiError.timedOut }

            var request = URLRequest(url: url)
            try authorized(&request)
            let (data, response) = try await sendWithRetry(request)
            try Self.checkHTTP(response, data)

            let parsed = try Self.parseResult(requestID: requestID, data: data)
            let status = parsed.status.lowercased()
            if status == "completed" || status == "succeeded" {
                guard !parsed.outputs.isEmpty else { throw MuapiError.noOutputs }
                return parsed
            }
            if status == "failed" || status == "error" || status == "canceled" || status == "cancelled" {
                throw MuapiError.http(0, "job \(status)")
            }
            // queued / processing → wait and retry.
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
    }

    /// Convenience: submit then poll to completion in one call.
    func generate(model: String, params: [String: Any]) async throws -> MuapiResult {
        let id = try await submit(model: model, params: params)
        return try await pollResult(requestID: id)
    }

    // MARK: Upload (for image-to-image / edit inputs)

    /// Upload binary media to muapi and get back a hosted URL to pass as an input
    /// (e.g. the source image for an edit). muapi exposes `POST /api/v1/upload` with
    /// multipart form data; the response carries the public URL.
    func uploadFile(data: Data, fileName: String, mimeType: String) async throws -> URL {
        let boundary = "muapi-\(UUID().uuidString)"
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("upload"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        try authorized(&request)
        request.httpBody = Self.multipartBody(boundary: boundary, fieldName: "file", fileName: fileName, mimeType: mimeType, data: data)

        let (respData, response) = try await transport.data(for: request)
        try Self.checkHTTP(response, respData)
        guard let obj = try? JSONSerialization.jsonObject(with: respData) as? [String: Any] else {
            throw MuapiError.decoding("upload response was not a JSON object")
        }
        let candidate = (obj["url"] ?? obj["file_url"] ?? obj["image_url"]) as? String
        guard let urlString = candidate, let url = URL(string: urlString) else {
            throw MuapiError.decoding("upload response missing url")
        }
        return url
    }

    static func multipartBody(boundary: String, fieldName: String, fileName: String, mimeType: String, data: Data) -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    // MARK: Cost estimate

    /// Best-effort per-call USD estimate from the curated catalog (offline) falling
    /// back to nil for unknown models. Used to show a confirm before a pricey job.
    func estimateCost(model: String) -> Double? {
        MuapiCatalog.cost(for: model)
    }

    // MARK: Text generation (multi-model delegation)

    /// Run a text/LLM model on muapi and return the generated text. Reuses the
    /// submit-then-poll lifecycle; muapi returns the answer in the result payload's
    /// `text`/`output`/`outputs` field. Used by the `chat_with_model` Coach tool.
    func generateText(model: String, prompt: String) async throws -> String {
        let id = try await submit(model: model, params: ["prompt": prompt])
        let deadline = Date().addingTimeInterval(pollTimeout)
        let url = Self.baseURL
            .appendingPathComponent("predictions")
            .appendingPathComponent(id)
            .appendingPathComponent("result")

        while true {
            try Task.checkCancellation()
            if Date() > deadline { throw MuapiError.timedOut }

            var request = URLRequest(url: url)
            try authorized(&request)
            let (data, response) = try await sendWithRetry(request)
            try Self.checkHTTP(response, data)

            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw MuapiError.decoding("text result was not a JSON object")
            }
            let status = ((obj["status"] as? String) ?? "processing").lowercased()
            if status == "completed" || status == "succeeded" {
                if let text = Self.extractText(obj), !text.isEmpty { return text }
                throw MuapiError.noOutputs
            }
            if status == "failed" || status == "error" {
                throw MuapiError.http(0, "job \(status)")
            }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
    }

    /// Pull text out of muapi's varied result shapes: `text`, `output` (string),
    /// `outputs:[string]`, or a `{text:…}`/`{content:…}` object.
    static func extractText(_ obj: [String: Any]) -> String? {
        if let t = obj["text"] as? String { return t }
        if let t = obj["output"] as? String { return t }
        if let arr = obj["outputs"] as? [Any] {
            let strings = arr.compactMap { $0 as? String }
            if !strings.isEmpty { return strings.joined(separator: "\n") }
            if let first = arr.first as? [String: Any] {
                if let t = (first["text"] ?? first["content"]) as? String { return t }
            }
        }
        if let dict = obj["output"] as? [String: Any] {
            return (dict["text"] ?? dict["content"]) as? String
        }
        return nil
    }

    // MARK: Catalog

    /// Fetch the live model catalog. No API key required by muapi, but we send it
    /// when present for consistency.
    func models() async throws -> [MuapiModel] {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("models"))
        if let key = (try? keyStore.readKey()) ?? nil, !key.isEmpty {
            request.setValue(key, forHTTPHeaderField: "x-api-key")
        }
        let (data, response) = try await transport.data(for: request)
        try Self.checkHTTP(response, data)
        return try Self.parseModels(data)
    }

    // MARK: Parsing helpers (static so tests can exercise them directly)

    static func checkHTTP(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            throw MuapiError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
    }

    static func parseResult(requestID: String, data: Data) throws -> MuapiResult {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MuapiError.decoding("result response was not a JSON object")
        }
        let status = (obj["status"] as? String) ?? "processing"
        let outputs = extractOutputs(obj)
        return MuapiResult(requestID: requestID, status: status, outputs: outputs)
    }

    /// muapi result shapes vary by model: `outputs: [url]`, `outputs: [{url:…}]`,
    /// or a top-level `output`. Normalize them all to `[URL]`.
    static func extractOutputs(_ obj: [String: Any]) -> [URL] {
        var urls: [String] = []
        func collect(_ any: Any?) {
            switch any {
            case let s as String:
                urls.append(s)
            case let arr as [Any]:
                arr.forEach { collect($0) }
            case let dict as [String: Any]:
                if let u = (dict["url"] ?? dict["image_url"] ?? dict["video_url"]) as? String { urls.append(u) }
            default:
                break
            }
        }
        collect(obj["outputs"])
        if urls.isEmpty { collect(obj["output"]) }
        return urls.compactMap { URL(string: $0) }
    }

    static func parseModels(_ data: Data) throws -> [MuapiModel] {
        // Catalog may be a bare array or wrapped in `{ models: [...] }`.
        if let arr = try? JSONDecoder().decode([MuapiModel].self, from: data) { return arr }
        struct Wrapper: Decodable { let models: [MuapiModel] }
        if let wrapped = try? JSONDecoder().decode(Wrapper.self, from: data) { return wrapped.models }
        throw MuapiError.decoding("could not parse model catalog")
    }
}

// MARK: - Curated catalog

/// A small, hand-picked set of muapi models surfaced in the UI as defaults so the
/// picker is useful before (or without) a live `/models` fetch. `name` values are the
/// model slugs muapi expects in `POST /api/v1/{model}`.
enum MuapiCatalog {
    static let image: [MuapiModel] = [
        MuapiModel(name: "nano-banana", category: "image", description: "Nano Banana (Gemini 2.5 Flash Image) — hyper-real, physics-aware, great editing", costUSD: 0.03),
        MuapiModel(name: "nano-banana-2", category: "image", description: "Nano Banana 2 (Gemini 3.1 Flash Image) — 4K, strong character consistency", costUSD: 0.06),
        MuapiModel(name: "nano-banana-pro", category: "image", description: "Nano Banana Pro — highest fidelity, complex text rendering", costUSD: 0.12),
        MuapiModel(name: "flux-schnell", category: "image", description: "Fast, low-cost text-to-image", costUSD: 0.003),
        MuapiModel(name: "flux-dev", category: "image", description: "Higher-fidelity FLUX", costUSD: 0.03),
        MuapiModel(name: "gpt-image-1", category: "image", description: "OpenAI image model", costUSD: 0.04),
        MuapiModel(name: "seedream-3", category: "image", description: "ByteDance Seedream", costUSD: 0.03),
    ]

    static let edit: [MuapiModel] = [
        MuapiModel(name: "nano-banana", category: "edit", description: "Nano Banana — conversational image editing & style transforms", costUSD: 0.03),
        MuapiModel(name: "flux-kontext", category: "edit", description: "Image-to-image editing", costUSD: 0.04),
        MuapiModel(name: "gpt-image-1-edit", category: "edit", description: "OpenAI image edit", costUSD: 0.04),
    ]

    static let video: [MuapiModel] = [
        MuapiModel(name: "openai-sora-2-text-to-video", category: "video", description: "OpenAI Sora 2 — cinematic 10s clips with synced audio", costUSD: 0.8),
        MuapiModel(name: "kling-v2-master", category: "video", description: "Kling text/image-to-video", costUSD: 1.4),
        MuapiModel(name: "veo3", category: "video", description: "Google Veo 3", costUSD: 3.0),
        MuapiModel(name: "seedance-1-lite", category: "video", description: "Fast, cheaper video", costUSD: 0.5),
    ]

    /// Text/LLM models reachable through muapi for delegated sub-questions.
    static let text: [MuapiModel] = [
        MuapiModel(name: "gpt-4o", category: "text", description: "OpenAI GPT-4o", costUSD: 0.01),
        MuapiModel(name: "claude-3-7-sonnet", category: "text", description: "Anthropic Claude Sonnet", costUSD: 0.01),
        MuapiModel(name: "deepseek-v3", category: "text", description: "DeepSeek V3", costUSD: 0.002),
        MuapiModel(name: "gemini-2-flash", category: "text", description: "Google Gemini Flash", costUSD: 0.002),
    ]

    static var all: [MuapiModel] { image + edit + video + text }

    static func defaultModel(for kind: MuapiMediaKind) -> String {
        switch kind {
        case .image: return "nano-banana"
        case .edit: return "nano-banana"
        case .video: return "openai-sora-2-text-to-video"
        }
    }

    static func cost(for model: String) -> Double? {
        all.first { $0.name == model }?.costUSD
    }
}

/// The three generation modalities the chatbox supports.
enum MuapiMediaKind: String, Codable, Equatable {
    case image
    case edit
    case video
}
