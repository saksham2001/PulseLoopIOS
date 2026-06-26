import Foundation
import XCTest
import CryptoKit
@testable import PulseLoop

// MARK: - Wearable OAuth2 infrastructure tests (Health-sync Track H / H2)
//
// Pure-logic coverage for the PKCE generator, the Keychain token-bundle store
// (against an in-memory backend), expiry/refresh decisions, the authorize-URL
// builder, and the OAuth callback parser. No network or real Keychain involved.
final class WearableOAuthTests: XCTestCase {

    // MARK: PKCE

    func testPKCEChallengeIsBase64URLSha256OfVerifier() {
        let pkce = PKCEChallenge(verifier: "test-verifier-1234567890")
        let expected = PKCEChallenge.base64URL(Data(SHA256.hash(data: Data(pkce.verifier.utf8))))
        XCTAssertEqual(pkce.challenge, expected)
        XCTAssertEqual(pkce.method, "S256")
    }

    func testPKCEBase64URLHasNoPaddingOrUnsafeChars() {
        let encoded = PKCEChallenge.base64URL(Data([0xff, 0xfe, 0xfd, 0xfc]))
        XCTAssertFalse(encoded.contains("="))
        XCTAssertFalse(encoded.contains("+"))
        XCTAssertFalse(encoded.contains("/"))
    }

    func testGeneratedVerifierIsLongAndUnique() {
        let a = PKCEChallenge.makeVerifier()
        let b = PKCEChallenge.makeVerifier()
        XCTAssertGreaterThanOrEqual(a.count, 43)
        XCTAssertNotEqual(a, b)
    }

    // MARK: Token store (in-memory backend)

    final class MemoryKeychain: KeychainBackend {
        private var store: [String: Data] = [:]
        private func key(_ s: String, _ a: String) -> String { "\(s)|\(a)" }
        func read(service: String, account: String) throws -> Data? { store[key(service, account)] }
        func save(_ data: Data, service: String, account: String) throws { store[key(service, account)] = data }
        func delete(service: String, account: String) throws { store[key(service, account)] = nil }
    }

    func testTokenBundleRoundTrips() throws {
        let backend = MemoryKeychain()
        let store = WearableTokenStore(provider: .fitbit, backend: backend)
        XCTAssertFalse(store.isConnected)

        let bundle = OAuthTokenBundle(
            accessToken: "abc",
            refreshToken: "refresh-xyz",
            expiresAt: Date().addingTimeInterval(3600),
            scope: "activity heartrate"
        )
        try store.save(bundle)
        XCTAssertTrue(store.isConnected)

        let loaded = try XCTUnwrap(store.read())
        XCTAssertEqual(loaded.accessToken, "abc")
        XCTAssertEqual(loaded.refreshToken, "refresh-xyz")
        XCTAssertEqual(loaded.scope, "activity heartrate")

        try store.clear()
        XCTAssertFalse(store.isConnected)
        XCTAssertNil(store.read())
    }

    func testTokenStoresAreIsolatedPerProvider() throws {
        let backend = MemoryKeychain()
        let fitbit = WearableTokenStore(provider: .fitbit, backend: backend)
        let google = WearableTokenStore(provider: .googleFit, backend: backend)
        try fitbit.save(OAuthTokenBundle(accessToken: "f", refreshToken: nil, expiresAt: Date().addingTimeInterval(60), scope: nil))
        XCTAssertTrue(fitbit.isConnected)
        XCTAssertFalse(google.isConnected, "providers must not share token slots")
    }

    // MARK: Expiry

    func testExpiryUsesSafetyMargin() {
        let almostExpired = OAuthTokenBundle(accessToken: "a", refreshToken: nil, expiresAt: Date().addingTimeInterval(30), scope: nil)
        XCTAssertTrue(almostExpired.isExpired(), "within the 60s margin should be treated as expired")
        let fresh = OAuthTokenBundle(accessToken: "a", refreshToken: nil, expiresAt: Date().addingTimeInterval(3600), scope: nil)
        XCTAssertFalse(fresh.isExpired())
    }

    // MARK: Authorize URL + config

    func testAuthorizeURLContainsPKCEAndScopes() {
        let config = WearableOAuthConfig(
            authorizeURL: URL(string: "https://example.com/auth")!,
            tokenURL: URL(string: "https://example.com/token")!,
            clientID: "client123",
            scopes: ["activity", "heartrate"],
            redirectURI: "pulseloop://oauth-callback/fitbit",
            extraAuthorizeItems: [URLQueryItem(name: "access_type", value: "offline")]
        )
        let pkce = PKCEChallenge(verifier: "verifier")
        let url = config.authorizeRequestURL(pkce: pkce, state: "state-1")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        XCTAssertEqual(value("response_type"), "code")
        XCTAssertEqual(value("client_id"), "client123")
        XCTAssertEqual(value("code_challenge"), pkce.challenge)
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertEqual(value("state"), "state-1")
        XCTAssertEqual(value("scope"), "activity heartrate")
        XCTAssertEqual(value("access_type"), "offline")
    }

    func testRedirectURIShapePerProvider() {
        XCTAssertEqual(WearableOAuthConfig.redirectURI(for: .fitbit), "pulseloop://oauth-callback/fitbit")
        XCTAssertEqual(WearableOAuthConfig.redirectURI(for: .googleFit), "pulseloop://oauth-callback/googleFit")
    }

    func testGoogleConfigRequestsOfflineConsent() {
        let config = WearableOAuthConfig.config(for: .googleFit)
        XCTAssertTrue(config.extraAuthorizeItems.contains { $0.name == "access_type" && $0.value == "offline" })
        XCTAssertTrue(config.extraAuthorizeItems.contains { $0.name == "prompt" && $0.value == "consent" })
    }

    // MARK: Callback parsing

    @MainActor
    func testCallbackParsingExtractsCodeAndState() throws {
        let auth = WearableOAuthAuthenticator(transport: URLSession.shared)
        let url = URL(string: "pulseloop://oauth-callback/fitbit?code=AUTH_CODE&state=xyz")!
        let (code, state) = try auth.parseCallback(url)
        XCTAssertEqual(code, "AUTH_CODE")
        XCTAssertEqual(state, "xyz")
    }

    @MainActor
    func testCallbackParsingSurfacesProviderError() {
        let auth = WearableOAuthAuthenticator(transport: URLSession.shared)
        let url = URL(string: "pulseloop://oauth-callback/fitbit?error=access_denied")!
        XCTAssertThrowsError(try auth.parseCallback(url))
    }

    func testFormEncodeEscapesValues() {
        let encoded = WearableOAuthAuthenticator.formEncode(["a": "x y", "b": "p/q"])
        XCTAssertTrue(encoded.contains("a=x%20y"))
        XCTAssertTrue(encoded.contains("b=p%2Fq"))
    }
}
