import Foundation

/// Fitbit Web API data source. Pulls steps + heart rate (and SpO2 where the user
/// granted it) for a given day and exposes them via `WearableDataSource`. Token
/// refresh is handled transparently; network is behind `HTTPTransport` so the
/// JSON → value mapping is unit-tested with canned responses.
///
/// API reference: https://dev.fitbit.com/build/reference/web-api/
@MainActor
final class FitbitDataSource: WearableDataSource {
    let sourceName = "Fitbit"
    private let provider = WearableProvider.fitbit
    private let store: WearableTokenStore
    private let authenticator: WearableOAuthAuthenticator
    private let transport: HTTPTransport

    init(
        store: WearableTokenStore = WearableTokenStore(provider: .fitbit),
        authenticator: WearableOAuthAuthenticator,
        transport: HTTPTransport = URLSession.shared
    ) {
        self.store = store
        self.authenticator = authenticator
        self.transport = transport
    }

    // MARK: WearableDataSource

    func requestAuthorization() async throws {
        _ = try await authenticator.connect(provider: provider)
    }

    func fetchLatestHeartRate() async throws -> Double? {
        let json = try await get("/1/user/-/activities/heart/date/today/1d.json")
        return FitbitDataSource.parseRestingHeartRate(json)
    }

    func fetchLatestSpO2() async throws -> Double? {
        // Fitbit exposes SpO2 per-day under a separate endpoint; tolerate absence.
        let json = try? await get("/1/user/-/spo2/date/today.json")
        guard let json else { return nil }
        return FitbitDataSource.parseSpO2(json)
    }

    func fetchSteps(for date: Date) async throws -> Int? {
        let day = FitbitDataSource.dateString(date)
        let json = try await get("/1/user/-/activities/date/\(day).json")
        return FitbitDataSource.parseSteps(json)
    }

    func fetchSleep(for date: Date) async throws -> (start: Date, end: Date, minutes: Int)? {
        let day = FitbitDataSource.dateString(date)
        let json = try? await get("/1.2/user/-/sleep/date/\(day).json")
        guard let json else { return nil }
        return FitbitDataSource.parseSleep(json)
    }

    // MARK: - Networking (token refresh + GET)

    private func validAccessToken() async throws -> String {
        guard var bundle = store.read() else { throw WearableOAuthError.notConfigured(provider) }
        if bundle.isExpired() {
            bundle = try await authenticator.refresh(bundle, provider: provider)
            try store.save(bundle)
        }
        return bundle.accessToken
    }

    private func get(_ path: String) async throws -> [String: Any] {
        let token = try await validAccessToken()
        var request = URLRequest(url: URL(string: "https://api.fitbit.com\(path)")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await NetworkRetry.send(request, transport: transport)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WearableOAuthError.tokenExchangeFailed("Fitbit HTTP error")
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

    /// `activities/date/<date>.json` → summary.steps.
    nonisolated static func parseSteps(_ json: [String: Any]) -> Int? {
        guard let summary = json["summary"] as? [String: Any] else { return nil }
        if let steps = summary["steps"] as? Int { return steps }
        if let steps = summary["steps"] as? Double { return Int(steps) }
        return nil
    }

    /// `activities/heart/date/today/1d.json` → activities-heart[0].value.restingHeartRate.
    nonisolated static func parseRestingHeartRate(_ json: [String: Any]) -> Double? {
        guard let arr = json["activities-heart"] as? [[String: Any]],
              let value = arr.first?["value"] as? [String: Any] else { return nil }
        if let rhr = value["restingHeartRate"] as? Int { return Double(rhr) }
        if let rhr = value["restingHeartRate"] as? Double { return rhr }
        return nil
    }

    /// `spo2/date/today.json` → value.avg (single-day shape).
    nonisolated static func parseSpO2(_ json: [String: Any]) -> Double? {
        guard let value = json["value"] as? [String: Any] else { return nil }
        if let avg = value["avg"] as? Double { return avg }
        if let avg = value["avg"] as? Int { return Double(avg) }
        return nil
    }

    /// `sleep/date/<date>.json` → summary totalMinutesAsleep + main sleep window.
    nonisolated static func parseSleep(_ json: [String: Any]) -> (start: Date, end: Date, minutes: Int)? {
        guard let sleeps = json["sleep"] as? [[String: Any]], !sleeps.isEmpty else { return nil }
        let main = sleeps.first { ($0["isMainSleep"] as? Bool) == true } ?? sleeps[0]
        guard let minutes = (main["minutesAsleep"] as? Int) ?? (main["duration"] as? Int).map({ $0 / 60000 }),
              let startStr = main["startTime"] as? String,
              let endStr = main["endTime"] as? String else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        // Fitbit sleep timestamps are local wall-clock with no zone offset. Parse
        // those in the device's time zone; appending "Z" would misread them as UTC
        // and shift the sleep window by the user's offset.
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = .current
        local.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        func parse(_ s: String) -> Date? { parser.date(from: s) ?? fallback.date(from: s) ?? local.date(from: s) }
        guard let start = parse(startStr), let end = parse(endStr) else { return nil }
        return (start, end, minutes)
    }
}
