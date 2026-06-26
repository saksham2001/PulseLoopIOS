import Foundation
import AuthenticationServices

enum AccountOAuthError: Error, LocalizedError {
    case notConfigured(AccountProvider)
    case userCancelled
    case stateMismatch
    case missingCode
    case tokenExchangeFailed(String)
    case noRefreshToken

    var errorDescription: String? {
        switch self {
        case .notConfigured(let p): return "\(p.rawValue) isn't configured yet (missing client id)."
        case .userCancelled: return "Sign-in was cancelled."
        case .stateMismatch: return "Security check failed (state mismatch)."
        case .missingCode: return "No authorization code was returned."
        case .tokenExchangeFailed(let m): return "Couldn't complete sign-in: \(m)"
        case .noRefreshToken: return "Session expired and can't be refreshed. Reconnect the account."
        }
    }
}

/// Drives the OAuth2 Authorization-Code + PKCE flow for **account** providers and
/// token exchange/refresh. The interactive browser step uses
/// `ASWebAuthenticationSession`; token HTTP is behind the injectable
/// `HTTPTransport` so exchange/refresh logic is unit-tested. Mirrors
/// `WearableOAuthAuthenticator`.
@MainActor
final class AccountOAuthAuthenticator: NSObject {
    private let transport: HTTPTransport

    init(transport: HTTPTransport = URLSession.shared) {
        self.transport = transport
    }

    /// Raw token endpoint response. Slack/Notion nest the token differently, so we
    /// tolerate both a top-level `access_token` and Slack's `authed_user.access_token`.
    private struct TokenResponse: Decodable {
        let access_token: String?
        let refresh_token: String?
        let expires_in: Double?
        let scope: String?
        let authed_user: AuthedUser?

        struct AuthedUser: Decodable {
            let access_token: String?
            let scope: String?
        }

        var resolvedToken: String? { access_token ?? authed_user?.access_token }
        var resolvedScope: String? { scope ?? authed_user?.scope }
    }

    func connect(provider: AccountProvider, presentationAnchor: ASPresentationAnchor? = nil) async throws -> OAuthTokenBundle {
        guard AccountOAuthConfig.isConfigured(provider), let config = AccountOAuthConfig.config(for: provider) else {
            throw AccountOAuthError.notConfigured(provider)
        }
        let pkce = PKCEChallenge()
        let state = UUID().uuidString
        let authURL = config.authorizeRequestURL(pkce: pkce, state: state)

        let callbackURL = try await presentWebAuth(url: authURL, anchor: presentationAnchor)
        let (code, returnedState) = try parseCallback(callbackURL)
        guard returnedState == state else { throw AccountOAuthError.stateMismatch }
        return try await exchangeCode(code, config: config, verifier: pkce.verifier)
    }

    func refresh(_ bundle: OAuthTokenBundle, provider: AccountProvider) async throws -> OAuthTokenBundle {
        guard let refresh = bundle.refreshToken else { throw AccountOAuthError.noRefreshToken }
        guard let config = AccountOAuthConfig.config(for: provider) else { throw AccountOAuthError.notConfigured(provider) }
        var params = [
            "grant_type": "refresh_token",
            "refresh_token": refresh,
            "client_id": config.clientID,
        ]
        let new = try await postToken(config.tokenURL, params: &params)
        guard let token = new.resolvedToken else { throw AccountOAuthError.tokenExchangeFailed("No access token in refresh response.") }
        return OAuthTokenBundle(
            accessToken: token,
            refreshToken: new.refresh_token ?? refresh,
            expiresAt: Date().addingTimeInterval(new.expires_in ?? 3600),
            scope: new.resolvedScope ?? bundle.scope
        )
    }

    // MARK: - Testable steps

    func parseCallback(_ url: URL) throws -> (code: String, state: String?) {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let err = comps?.queryItems?.first(where: { $0.name == "error" })?.value {
            throw AccountOAuthError.tokenExchangeFailed(err)
        }
        guard let code = comps?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AccountOAuthError.missingCode
        }
        let state = comps?.queryItems?.first(where: { $0.name == "state" })?.value
        return (code, state)
    }

    private func exchangeCode(_ code: String, config: AccountOAuthConfig, verifier: String) async throws -> OAuthTokenBundle {
        var params = [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": config.clientID,
            "redirect_uri": config.redirectURI,
            "code_verifier": verifier,
        ]
        let resp = try await postToken(config.tokenURL, params: &params)
        guard let token = resp.resolvedToken else { throw AccountOAuthError.tokenExchangeFailed("No access token in response.") }
        return OAuthTokenBundle(
            accessToken: token,
            refreshToken: resp.refresh_token,
            expiresAt: Date().addingTimeInterval(resp.expires_in ?? 3600),
            scope: resp.resolvedScope
        )
    }

    private func postToken(_ url: URL, params: inout [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = AccountOAuthAuthenticator.formEncode(params).data(using: .utf8)

        let (data, response) = try await NetworkRetry.send(request, transport: transport)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AccountOAuthError.tokenExchangeFailed(body.isEmpty ? "HTTP error" : body)
        }
        do {
            return try JSONDecoder().decode(TokenResponse.self, from: data)
        } catch {
            throw AccountOAuthError.tokenExchangeFailed("Unexpected token response.")
        }
    }

    nonisolated static func formEncode(_ params: [String: String]) -> String {
        params.map { key, value in
            let encoded = value.addingPercentEncoding(withAllowedCharacters: .accountQueryAllowed) ?? value
            return "\(key)=\(encoded)"
        }.joined(separator: "&")
    }

    // MARK: - Interactive browser session

    private var session: ASWebAuthenticationSession?

    private func presentWebAuth(url: URL, anchor: ASPresentationAnchor?) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: AccountOAuthConfig.callbackScheme
            ) { callbackURL, error in
                if let error {
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        continuation.resume(throwing: AccountOAuthError.userCancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: AccountOAuthError.missingCode)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                continuation.resume(throwing: AccountOAuthError.tokenExchangeFailed("Couldn't start the sign-in session."))
            }
        }
    }
}

extension AccountOAuthAuthenticator: ASWebAuthenticationPresentationContextProviding {
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
    static let accountQueryAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
