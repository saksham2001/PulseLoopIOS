import Foundation
import AuthenticationServices

enum WearableOAuthError: Error, LocalizedError {
    case notConfigured(WearableProvider)
    case userCancelled
    case stateMismatch
    case missingCode
    case tokenExchangeFailed(String)
    case noRefreshToken

    var errorDescription: String? {
        switch self {
        case .notConfigured(let p): return "\(p.displayName) isn't configured yet (missing client id)."
        case .userCancelled: return "Sign-in was cancelled."
        case .stateMismatch: return "Security check failed (state mismatch)."
        case .missingCode: return "No authorization code was returned."
        case .tokenExchangeFailed(let m): return "Couldn't complete sign-in: \(m)"
        case .noRefreshToken: return "Session expired and can't be refreshed. Reconnect the account."
        }
    }
}

/// Raw token endpoint response shared by Fitbit + Google (snake_case JSON).
private struct TokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Double?
    let scope: String?
}

/// Drives the OAuth2 Authorization-Code + PKCE flow and token exchange/refresh.
/// The interactive browser step uses `ASWebAuthenticationSession`; token HTTP is
/// behind the injectable `HTTPTransport` so exchange/refresh logic is unit-tested.
@MainActor
final class WearableOAuthAuthenticator: NSObject {
    private let transport: HTTPTransport

    init(transport: HTTPTransport = URLSession.shared) {
        self.transport = transport
    }

    /// Full interactive connect: opens the provider's consent page, validates the
    /// callback, and exchanges the code for a token bundle.
    func connect(provider: WearableProvider, presentationAnchor: ASPresentationAnchor? = nil) async throws -> OAuthTokenBundle {
        guard WearableOAuthConfig.isConfigured(provider) else { throw WearableOAuthError.notConfigured(provider) }
        let config = WearableOAuthConfig.config(for: provider)
        let pkce = PKCEChallenge()
        let state = UUID().uuidString
        let authURL = config.authorizeRequestURL(pkce: pkce, state: state)

        let callbackURL = try await presentWebAuth(url: authURL, anchor: presentationAnchor)
        let (code, returnedState) = try parseCallback(callbackURL)
        guard returnedState == state else { throw WearableOAuthError.stateMismatch }
        return try await exchangeCode(code, config: config, verifier: pkce.verifier)
    }

    /// Refresh an expired bundle using its refresh token (refresh_token grant).
    func refresh(_ bundle: OAuthTokenBundle, provider: WearableProvider) async throws -> OAuthTokenBundle {
        guard let refresh = bundle.refreshToken else { throw WearableOAuthError.noRefreshToken }
        let config = WearableOAuthConfig.config(for: provider)
        var params = [
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": config.clientID,
        ]
        // Fitbit/Google both accept client_id in the body for public PKCE clients.
        let new = try await postToken(config.tokenURL, params: &params)
        // Providers may omit a new refresh token; keep the old one if so.
        return OAuthTokenBundle(
            accessToken: new.access_token,
            refreshToken: new.refresh_token ?? refresh,
            expiresAt: Date().addingTimeInterval(new.expires_in ?? 3600),
            scope: new.scope ?? bundle.scope
        )
    }

    // MARK: - Steps (also unit-testable except presentWebAuth)

    func parseCallback(_ url: URL) throws -> (code: String, state: String?) {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let err = comps?.queryItems?.first(where: { $0.name == "error" })?.value {
            throw WearableOAuthError.tokenExchangeFailed(err)
        }
        guard let code = comps?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw WearableOAuthError.missingCode
        }
        let state = comps?.queryItems?.first(where: { $0.name == "state" })?.value
        return (code, state)
    }

    private func exchangeCode(_ code: String, config: WearableOAuthConfig, verifier: String) async throws -> OAuthTokenBundle {
        var params = [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": config.clientID,
            "redirect_uri": config.redirectURI,
            "code_verifier": verifier,
        ]
        let resp = try await postToken(config.tokenURL, params: &params)
        return OAuthTokenBundle(
            accessToken: resp.access_token,
            refreshToken: resp.refresh_token,
            expiresAt: Date().addingTimeInterval(resp.expires_in ?? 3600),
            scope: resp.scope
        )
    }

    private func postToken(_ url: URL, params: inout [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = WearableOAuthAuthenticator.formEncode(params).data(using: .utf8)

        let (data, response) = try await NetworkRetry.send(request, transport: transport)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw WearableOAuthError.tokenExchangeFailed(body.isEmpty ? "HTTP error" : body)
        }
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw WearableOAuthError.tokenExchangeFailed("Unexpected token response.")
        }
    }

    nonisolated static func formEncode(_ params: [String: String]) -> String {
        params.map { key, value in
            let encoded = value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? value
            return "\(key)=\(encoded)"
        }.joined(separator: "&")
    }

    // MARK: - Interactive browser session

    private var session: ASWebAuthenticationSession?

    private func presentWebAuth(url: URL, anchor: ASPresentationAnchor?) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: WearableOAuthConfig.callbackScheme
            ) { callbackURL, error in
                if let error {
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        continuation.resume(throwing: WearableOAuthError.userCancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: WearableOAuthError.missingCode)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: WearableOAuthError.tokenExchangeFailed("Couldn't start the sign-in session."))
            }
        }
    }
}

extension WearableOAuthAuthenticator: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        #if canImport(UIKit)
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        return scene?.keyWindow ?? ASPresentationAnchor()
        #else
        return ASPresentationAnchor()
        #endif
    }
}

private extension CharacterSet {
    /// Allowed characters for x-www-form-urlencoded values (RFC 3986 unreserved).
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}

#if canImport(UIKit)
import UIKit
private extension UIWindowScene {
    var keyWindow: UIWindow? { windows.first { $0.isKeyWindow } }
}
#endif
