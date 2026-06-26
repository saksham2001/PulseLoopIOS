import Foundation

/// Oura Ring API v2 data source. Pulls daily activity (steps), heart rate, SpO2,
/// and sleep over OAuth2 and exposes them via `WearableDataSource`. Network is
/// behind the injectable `HTTPTransport` so the JSON → value mapping is unit-tested
/// with canned responses; token refresh is handled transparently.
///
/// API reference: https://cloud.ouraring.com/v2/docs
@MainActor
final class OuraDataSource: WearableDataSource {
    let sourceName = "Oura Ring"
    private let provider = WearableProvider.oura
    private let store: WearableTokenStore
    private let authenticator: WearableOAuthAuthenticator
    private let transport: HTTPTransport

    init(
        store: WearableTokenStore = WearableTokenStore(provider: .oura),
        authenticator: WearableOAuthAuthenticator,
        transport: HTTPTransport = URLSession.shared
    ) {
        self.store = store
        self.authenticator = authenticator
        self.transport = transport
    }

    private static let base = "https://api.ouraring.com/v2/usercollection"

    // MARK: WearableDataSource

    func requestAuthorization() async throws {
        _ = try await authenticator.connect(provider: provider)
    }

    func fetchLatestHeartRate() async throws -> Double? {
        // Average resting HR from today's daily_readiness/heart-rate stream.
        let day = OuraDataSource.dateString(Date())
        let json = try await get("/heartrate", query: [
            // Use "Z" rather than "+00:00": URLComponents leaves "+" unencoded in a
            // query value, so the server would read it as a space and reject the range.
            URLQueryItem(name: "start_datetime", value: "\(day)T00:00:00Z"),
        ])
        return OuraDataSource.parseAverageHeartRate(json)
    }

    func fetchLatestSpO2() async throws -> Double? {
        let day = OuraDataSource.dateString(Date())
        let json = try? await get("/daily_spo2", query: [
            URLQueryItem(name: "start_date", value: day),
            URLQueryItem(name: "end_date", value: day),
        ])
        guard let json else { return nil }
        return OuraDataSource.parseSpO2(json)
    }

    func fetchSteps(for date: Date) async throws -> Int? {
        let day = OuraDataSource.dateString(date)
        let json = try await get("/daily_activity", query: [
            URLQueryItem(name: "start_date", value: day),
            URLQueryItem(name: "end_date", value: day),
        ])
        return OuraDataSource.parseSteps(json)
    }

    func fetchSleep(for date: Date) async throws -> (start: Date, end: Date, minutes: Int)? {
        let day = OuraDataSource.dateString(date)
        let json = try? await get("/sleep", query: [
            URLQueryItem(name: "start_date", value: day),
            URLQueryItem(name: "end_date", value: day),
        ])
        guard let json else { return nil }
        return OuraDataSource.parseSleep(json)
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

    private func get(_ path: String, query: [URLQueryItem] = []) async throws -> [String: Any] {
        let token = try await validAccessToken()
        var components = URLComponents(string: "\(Self.base)\(path)")!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await NetworkRetry.send(request, transport: transport)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WearableOAuthError.tokenExchangeFailed("Oura HTTP error")
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    // MARK: - Pure parsers (unit-tested)

    nonisolated static func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    /// `daily_activity` → data[last].steps.
    nonisolated static func parseSteps(_ json: [String: Any]) -> Int? {
        guard let data = json["data"] as? [[String: Any]], let last = data.last else { return nil }
        if let steps = last["steps"] as? Int { return steps }
        if let steps = last["steps"] as? Double { return Int(steps) }
        return nil
    }

    /// `heartrate` → average of data[].bpm.
    nonisolated static func parseAverageHeartRate(_ json: [String: Any]) -> Double? {
        guard let data = json["data"] as? [[String: Any]], !data.isEmpty else { return nil }
        var sum = 0.0
        var count = 0
        for point in data {
            if let bpm = point["bpm"] as? Double { sum += bpm; count += 1 }
            else if let bpm = point["bpm"] as? Int { sum += Double(bpm); count += 1 }
        }
        return count > 0 ? sum / Double(count) : nil
    }

    /// `daily_spo2` → data[last].spo2_percentage.average.
    nonisolated static func parseSpO2(_ json: [String: Any]) -> Double? {
        guard let data = json["data"] as? [[String: Any]], let last = data.last else { return nil }
        if let pct = last["spo2_percentage"] as? [String: Any] {
            if let avg = pct["average"] as? Double { return avg }
            if let avg = pct["average"] as? Int { return Double(avg) }
        }
        return nil
    }

    /// `sleep` → main (longest) session: total_sleep_duration (seconds) + bedtime window.
    nonisolated static func parseSleep(_ json: [String: Any]) -> (start: Date, end: Date, minutes: Int)? {
        guard let data = json["data"] as? [[String: Any]], !data.isEmpty else { return nil }
        let main = data.max { lhs, rhs in
            ((lhs["total_sleep_duration"] as? Int) ?? 0) < ((rhs["total_sleep_duration"] as? Int) ?? 0)
        } ?? data[0]
        guard let seconds = (main["total_sleep_duration"] as? Int) ?? (main["total_sleep_duration"] as? Double).map({ Int($0) }),
              let startStr = main["bedtime_start"] as? String,
              let endStr = main["bedtime_end"] as? String else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        func parse(_ s: String) -> Date? { parser.date(from: s) ?? fallback.date(from: s) }
        guard let start = parse(startStr), let end = parse(endStr) else { return nil }
        return (start, end, seconds / 60)
    }
}
