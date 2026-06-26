import Foundation

/// Whoop Developer Platform (v1) data source. Pulls recovery (resting HR + HRV),
/// cycle strain, and sleep over OAuth2 and exposes them via `WearableDataSource`.
/// Whoop has no step count, so `fetchSteps` returns nil. Network is behind the
/// injectable `HTTPTransport` so JSON → value mapping is unit-tested.
///
/// API reference: https://developer.whoop.com/api
@MainActor
final class WhoopDataSource: WearableDataSource {
    let sourceName = "Whoop"
    private let provider = WearableProvider.whoop
    private let store: WearableTokenStore
    private let authenticator: WearableOAuthAuthenticator
    private let transport: HTTPTransport

    init(
        store: WearableTokenStore = WearableTokenStore(provider: .whoop),
        authenticator: WearableOAuthAuthenticator,
        transport: HTTPTransport = URLSession.shared
    ) {
        self.store = store
        self.authenticator = authenticator
        self.transport = transport
    }

    private static let base = "https://api.prod.whoop.com/developer/v1"

    // MARK: WearableDataSource

    func requestAuthorization() async throws {
        _ = try await authenticator.connect(provider: provider)
    }

    func fetchLatestHeartRate() async throws -> Double? {
        // Resting heart rate lives on the latest recovery record.
        let json = try await get("/recovery", query: [URLQueryItem(name: "limit", value: "1")])
        return WhoopDataSource.parseRestingHeartRate(json)
    }

    func fetchLatestSpO2() async throws -> Double? {
        // Whoop exposes SpO2 only on certain bands; tolerate absence.
        let json = try? await get("/recovery", query: [URLQueryItem(name: "limit", value: "1")])
        guard let json else { return nil }
        return WhoopDataSource.parseSpO2(json)
    }

    func fetchSteps(for date: Date) async throws -> Int? {
        // Whoop does not track steps.
        nil
    }

    func fetchSleep(for date: Date) async throws -> (start: Date, end: Date, minutes: Int)? {
        let json = try? await get("/activity/sleep", query: [URLQueryItem(name: "limit", value: "1")])
        guard let json else { return nil }
        return WhoopDataSource.parseSleep(json)
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
            throw WearableOAuthError.tokenExchangeFailed("Whoop HTTP error")
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    // MARK: - Pure parsers (unit-tested)

    /// `recovery?limit=1` → records[0].score.resting_heart_rate.
    nonisolated static func parseRestingHeartRate(_ json: [String: Any]) -> Double? {
        guard let score = firstRecordScore(json) else { return nil }
        if let rhr = score["resting_heart_rate"] as? Double { return rhr }
        if let rhr = score["resting_heart_rate"] as? Int { return Double(rhr) }
        return nil
    }

    /// `recovery?limit=1` → records[0].score.spo2_percentage.
    nonisolated static func parseSpO2(_ json: [String: Any]) -> Double? {
        guard let score = firstRecordScore(json) else { return nil }
        if let spo2 = score["spo2_percentage"] as? Double { return spo2 }
        if let spo2 = score["spo2_percentage"] as? Int { return Double(spo2) }
        return nil
    }

    /// `recovery?limit=1` → records[0].score.hrv_rmssd_milli (resting HRV, ms).
    nonisolated static func parseHRV(_ json: [String: Any]) -> Double? {
        guard let score = firstRecordScore(json) else { return nil }
        if let hrv = score["hrv_rmssd_milli"] as? Double { return hrv }
        if let hrv = score["hrv_rmssd_milli"] as? Int { return Double(hrv) }
        return nil
    }

    /// `activity/sleep?limit=1` → records[0]: start/end + score.stage_summary
    /// total_in_bed minus awake, in milliseconds.
    nonisolated static func parseSleep(_ json: [String: Any]) -> (start: Date, end: Date, minutes: Int)? {
        guard let records = json["records"] as? [[String: Any]], let rec = records.first,
              let startStr = rec["start"] as? String, let endStr = rec["end"] as? String else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        func parse(_ s: String) -> Date? { parser.date(from: s) ?? fallback.date(from: s) }
        guard let start = parse(startStr), let end = parse(endStr) else { return nil }
        var minutes = Int(end.timeIntervalSince(start) / 60)
        if let score = rec["score"] as? [String: Any],
           let stages = score["stage_summary"] as? [String: Any],
           let bedMilli = (stages["total_in_bed_time_milli"] as? Int) ?? (stages["total_in_bed_time_milli"] as? Double).map({ Int($0) }),
           let awakeMilli = (stages["total_awake_time_milli"] as? Int) ?? (stages["total_awake_time_milli"] as? Double).map({ Int($0) }) {
            minutes = max(0, (bedMilli - awakeMilli) / 60000)
        }
        return (start, end, minutes)
    }

    nonisolated private static func firstRecordScore(_ json: [String: Any]) -> [String: Any]? {
        guard let records = json["records"] as? [[String: Any]], let first = records.first else { return nil }
        return first["score"] as? [String: Any]
    }
}
