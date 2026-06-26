import Foundation

/// Garmin Health API data source — placeholder.
///
/// Garmin's Health API authenticates with OAuth 1.0a (request token → user
/// authorize → access token), which the app's PKCE / Authorization-Code
/// `WearableOAuthAuthenticator` cannot drive without a server-side signing
/// component. Rather than ship a fake "Connect" button, this source honestly
/// fails fast with `notConfigured`, and `WearableOAuthConfig.isFlowSupported`
/// keeps Garmin's Connect row in an honest `.unavailable` state until a backend
/// exists. The shape conforms to `WearableDataSource` so the manager treats it
/// uniformly and lights up automatically once a real flow lands.
@MainActor
final class GarminDataSource: WearableDataSource {
    let sourceName = "Garmin"
    private let provider = WearableProvider.garmin

    init(
        store: WearableTokenStore = WearableTokenStore(provider: .garmin),
        authenticator: WearableOAuthAuthenticator,
        transport: HTTPTransport = URLSession.shared
    ) {
        // Stored for interface symmetry with the other sources; unused until a
        // Garmin-compatible (OAuth 1.0a) authenticator/backend is added.
        _ = store
        _ = authenticator
        _ = transport
    }

    func requestAuthorization() async throws { throw WearableOAuthError.notConfigured(provider) }
    func fetchLatestHeartRate() async throws -> Double? { nil }
    func fetchLatestSpO2() async throws -> Double? { nil }
    func fetchSteps(for date: Date) async throws -> Int? { nil }
    func fetchSleep(for date: Date) async throws -> (start: Date, end: Date, minutes: Int)? { nil }
}
