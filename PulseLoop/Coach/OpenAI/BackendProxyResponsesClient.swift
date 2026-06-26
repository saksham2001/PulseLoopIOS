import Foundation

/// `ResponsesClient` that routes the coach request through the PulseLoop AI
/// backend proxy instead of calling the model provider directly (roadmap E3
/// enforcement seam).
///
/// Why a proxy: in a public build the provider (OpenRouter) key must never live
/// on-device, and credits must be enforced somewhere the user can't bypass. The
/// proxy holds the key, debits the **server-authoritative** credit ledger, and
/// accepts the same `/v1/responses` body the orchestrator already builds (the
/// server translates it to OpenRouter chat-completions) — so the orchestrator code
/// path is identical regardless of provider.
///
/// Wire contract (so the server can be implemented independently):
/// - `POST {baseURL}/v1/coach/responses`
/// - `Authorization: Bearer {sessionToken}` (the user's PulseLoop session, NOT a
///   provider key — the server attaches its own key).
/// - Body: the verbatim OpenAI Responses request body.
/// - On success: an OpenAI Responses-shaped JSON, optionally augmented with a
///   top-level `pulseloop_credits` object (`{ "balance": Int }`) the client trusts
///   as the authoritative balance. The returned `id` resumes the conversation on
///   the next turn's `previous_response_id`.
/// - On `402 Payment Required`: the server refused for lack of credits.
struct BackendProxyResponsesClient: ResponsesClient {
    let baseURL: URL
    let sessionToken: String?
    let session: URLSession

    init(baseURL: URL, sessionToken: String?, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.sessionToken = sessionToken
        self.session = session
    }

    func send(requestBody: Data) async throws -> OpenAIResponse {
        let endpoint = baseURL.appendingPathComponent("v1/coach/responses")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = sessionToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = requestBody
        request.timeoutInterval = 60

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ResponsesError.transport(error)
        }

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 402 {
                throw ResponsesError.insufficientCredits
            }
            if !(200...299).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw ResponsesError.http(status: http.statusCode, body: body)
            }
        }

        // Let the server be the source of truth for the balance when it reports one.
        if let balance = Self.serverBalance(from: data) {
            await MainActor.run { CreditsLedger.shared.syncAuthoritativeBalance(balance) }
        }
        return try OpenAIResponse.parse(data)
    }

    /// Extracts an optional `pulseloop_credits.balance` field the proxy may attach.
    private static func serverBalance(from data: Data) -> Int? {
        guard
            let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
            let credits = root["pulseloop_credits"] as? [String: Any],
            let balance = credits["balance"] as? Int
        else { return nil }
        return balance
    }
}
