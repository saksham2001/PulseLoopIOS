import Foundation

/// Google Fit REST API data source. On iOS, Google's "health" data is the Fitness
/// (Google Fit) REST API over OAuth2 — Android's Health Connect is a separate,
/// Android-only API and out of scope. Pulls steps + heart rate for a day via the
/// `dataset:aggregate` endpoint and exposes them through `WearableDataSource`.
///
/// API reference: https://developers.google.com/fit/rest
@MainActor
final class GoogleFitDataSource: WearableDataSource {
    let sourceName = "Google Fit"
    private let provider = WearableProvider.googleFit
    private let store: WearableTokenStore
    private let authenticator: WearableOAuthAuthenticator
    private let transport: HTTPTransport

    init(
        store: WearableTokenStore = WearableTokenStore(provider: .googleFit),
        authenticator: WearableOAuthAuthenticator,
        transport: HTTPTransport = URLSession.shared
    ) {
        self.store = store
        self.authenticator = authenticator
        self.transport = transport
    }

    private static let aggregateURL = URL(string: "https://www.googleapis.com/fitness/v1/users/me/dataset:aggregate")!

    // MARK: WearableDataSource

    func requestAuthorization() async throws {
        _ = try await authenticator.connect(provider: provider)
    }

    func fetchLatestHeartRate() async throws -> Double? {
        let (start, end) = GoogleFitDataSource.dayWindow(Date())
        let body = GoogleFitDataSource.aggregateBody(dataTypeName: "com.google.heart_rate.bpm", startMs: start, endMs: end)
        let json = try await post(body)
        return GoogleFitDataSource.parseAverageValue(json)
    }

    func fetchLatestSpO2() async throws -> Double? {
        // Google Fit doesn't expose SpO2 through the standard fitness scopes.
        nil
    }

    func fetchSteps(for date: Date) async throws -> Int? {
        let (start, end) = GoogleFitDataSource.dayWindow(date)
        let body = GoogleFitDataSource.aggregateBody(dataTypeName: "com.google.step_count.delta", startMs: start, endMs: end)
        let json = try await post(body)
        return GoogleFitDataSource.parseSumInt(json)
    }

    func fetchSleep(for date: Date) async throws -> (start: Date, end: Date, minutes: Int)? {
        // Sleep sessions require the sessions API + sleep scope; deferred.
        nil
    }

    // MARK: - Networking

    private func validAccessToken() async throws -> String {
        guard var bundle = store.read() else { throw WearableOAuthError.notConfigured(provider) }
        if bundle.isExpired() {
            bundle = try await authenticator.refresh(bundle, provider: provider)
            try store.save(bundle)
        }
        return bundle.accessToken
    }

    private func post(_ body: [String: Any]) async throws -> [String: Any] {
        let token = try await validAccessToken()
        var request = URLRequest(url: Self.aggregateURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await NetworkRetry.send(request, transport: transport)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WearableOAuthError.tokenExchangeFailed("Google Fit HTTP error")
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    // MARK: - Pure builders + parsers (unit-tested)

    /// Start/end of the local day in epoch milliseconds.
    nonisolated static func dayWindow(_ date: Date, calendar: Calendar = .current) -> (Int, Int) {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        return (Int(start.timeIntervalSince1970 * 1000), Int(end.timeIntervalSince1970 * 1000))
    }

    nonisolated static func aggregateBody(dataTypeName: String, startMs: Int, endMs: Int) -> [String: Any] {
        [
            "aggregateBy": [["dataTypeName": dataTypeName]],
            "bucketByTime": ["durationMillis": endMs - startMs],
            "startTimeMillis": startMs,
            "endTimeMillis": endMs,
        ]
    }

    /// Sum integer values across all buckets/points (e.g. step deltas).
    nonisolated static func parseSumInt(_ json: [String: Any]) -> Int? {
        let points = allPoints(json)
        guard !points.isEmpty else { return nil }
        var total = 0
        var found = false
        for point in points {
            for v in (point["value"] as? [[String: Any]]) ?? [] {
                if let i = v["intVal"] as? Int { total += i; found = true }
                else if let d = v["fpVal"] as? Double { total += Int(d); found = true }
            }
        }
        return found ? total : nil
    }

    /// Average floating-point value across points (e.g. heart-rate bpm).
    nonisolated static func parseAverageValue(_ json: [String: Any]) -> Double? {
        let points = allPoints(json)
        var sum = 0.0
        var count = 0
        for point in points {
            for v in (point["value"] as? [[String: Any]]) ?? [] {
                if let d = v["fpVal"] as? Double { sum += d; count += 1 }
                else if let i = v["intVal"] as? Int { sum += Double(i); count += 1 }
            }
        }
        return count > 0 ? sum / Double(count) : nil
    }

    nonisolated private static func allPoints(_ json: [String: Any]) -> [[String: Any]] {
        let buckets = (json["bucket"] as? [[String: Any]]) ?? []
        return buckets.flatMap { bucket -> [[String: Any]] in
            let datasets = (bucket["dataset"] as? [[String: Any]]) ?? []
            return datasets.flatMap { ($0["point"] as? [[String: Any]]) ?? [] }
        }
    }
}
