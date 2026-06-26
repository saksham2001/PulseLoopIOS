import Foundation
import os

/// Minimal HTTP transport seam so networking can be unit-tested without hitting the
/// real network. `URLSession` conforms out of the box; tests inject a fake.
protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {}

/// Shared retry/backoff for transient network failures, generalized from the
/// `MuapiClient.sendWithRetry` pattern so every service gets the same resilience.
///
/// Retries on URL/transport errors and on HTTP 5xx / 429, with exponential backoff.
/// Non-transient HTTP responses (2xx/4xx other than 429) return immediately — the
/// caller decides how to interpret the status code. Cancellation propagates.
enum NetworkRetry {
    static func send(
        _ request: URLRequest,
        transport: HTTPTransport,
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 0.4
    ) async throws -> (Data, URLResponse) {
        var attempt = 0
        var delay = initialDelay
        while true {
            try Task.checkCancellation()
            attempt += 1
            do {
                let (data, response) = try await transport.data(for: request)
                if let http = response as? HTTPURLResponse,
                   http.statusCode >= 500 || http.statusCode == 429,
                   attempt < maxAttempts {
                    AppLog.network.debug("Retrying \(request.url?.absoluteString ?? "?", privacy: .public) after HTTP \(http.statusCode) (attempt \(attempt)/\(maxAttempts))")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    delay *= 2
                    continue
                }
                return (data, response)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard attempt < maxAttempts else {
                    AppLog.network.error("Request failed after \(attempt) attempts: \(String(describing: error), privacy: .public)")
                    throw error
                }
                AppLog.network.debug("Retrying after transport error (attempt \(attempt)/\(maxAttempts)): \(String(describing: error), privacy: .public)")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                delay *= 2
            }
        }
    }
}

/// A small thread-safe in-memory cache with per-entry TTL, for read-only network
/// lookups (drug/food databases) where repeated identical requests are common and the
/// data changes slowly. Keyed by an arbitrary string (typically the request URL).
final class ResponseCache: @unchecked Sendable {
    struct Entry {
        let data: Data
        let expires: Date
    }

    private var store: [String: Entry] = [:]
    private let lock = NSLock()
    private let ttl: TimeInterval

    init(ttl: TimeInterval = 60 * 60) { self.ttl = ttl }

    func value(for key: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = store[key] else { return nil }
        if entry.expires < Date() {
            store[key] = nil
            return nil
        }
        return entry.data
    }

    func set(_ data: Data, for key: String) {
        lock.lock(); defer { lock.unlock() }
        store[key] = Entry(data: data, expires: Date().addingTimeInterval(ttl))
    }
}
