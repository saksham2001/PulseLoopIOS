import Foundation

/// Static OAuth2 endpoint + scope configuration per provider. Client IDs are read
/// from Info.plist (`FITBIT_CLIENT_ID` / `GOOGLE_CLIENT_ID`) so secrets aren't
/// hard-coded; a missing/placeholder id makes the provider "needs configuration".
struct WearableOAuthConfig {
    let authorizeURL: URL
    let tokenURL: URL
    let clientID: String
    let scopes: [String]
    let redirectURI: String
    /// Extra query items some providers require on the authorize request.
    let extraAuthorizeItems: [URLQueryItem]

    static let callbackScheme = "pulseloop"

    static func redirectURI(for provider: WearableProvider) -> String {
        "\(callbackScheme)://oauth-callback/\(provider.rawValue)"
    }

    static func clientID(for provider: WearableProvider) -> String {
        let key: String
        switch provider {
        case .fitbit: key = "FITBIT_CLIENT_ID"
        case .googleFit: key = "GOOGLE_CLIENT_ID"
        case .oura: key = "OURA_CLIENT_ID"
        case .whoop: key = "WHOOP_CLIENT_ID"
        case .garmin: key = "GARMIN_CLIENT_ID"
        }
        let raw = (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether the provider's OAuth flow is supported by our PKCE authenticator.
    /// Garmin's Health API uses OAuth 1.0a, which our PKCE/auth-code authenticator
    /// can't drive, so we honestly mark it unsupported until a backend exists.
    static func isFlowSupported(_ provider: WearableProvider) -> Bool {
        switch provider {
        case .fitbit, .googleFit, .oura, .whoop: return true
        case .garmin: return false
        }
    }

    /// A human-readable reason a provider can't connect, or `nil` when it can
    /// (given a real client id). Lets the UI render an honest `.unavailable`.
    static func unsupportedReason(for provider: WearableProvider) -> String? {
        switch provider {
        case .garmin:
            return "Garmin uses OAuth 1.0a (Health API) and needs a backend to connect. Not yet available."
        default:
            return nil
        }
    }

    /// True when a real (non-placeholder) client id is configured for this provider
    /// AND its OAuth flow is supported by this build.
    static func isConfigured(_ provider: WearableProvider) -> Bool {
        guard isFlowSupported(provider) else { return false }
        let id = clientID(for: provider)
        return !id.isEmpty && !id.hasPrefix("YOUR_") && !id.hasPrefix("REPLACE") && id != "REPLACE_ME"
    }

    static func config(for provider: WearableProvider) -> WearableOAuthConfig {
        let redirect = redirectURI(for: provider)
        switch provider {
        case .fitbit:
            return WearableOAuthConfig(
                authorizeURL: URL(string: "https://www.fitbit.com/oauth2/authorize")!,
                tokenURL: URL(string: "https://api.fitbit.com/oauth2/token")!,
                clientID: clientID(for: provider),
                scopes: ["activity", "heartrate", "sleep", "oxygen_saturation"],
                redirectURI: redirect,
                extraAuthorizeItems: []
            )
        case .googleFit:
            return WearableOAuthConfig(
                authorizeURL: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
                tokenURL: URL(string: "https://oauth2.googleapis.com/token")!,
                clientID: clientID(for: provider),
                scopes: [
                    "https://www.googleapis.com/auth/fitness.activity.read",
                    "https://www.googleapis.com/auth/fitness.heart_rate.read",
                ],
                redirectURI: redirect,
                // Google requires these to return a refresh token on installed apps.
                extraAuthorizeItems: [
                    URLQueryItem(name: "access_type", value: "offline"),
                    URLQueryItem(name: "prompt", value: "consent"),
                ]
            )
        case .oura:
            // Oura API v2 OAuth2 (Authorization Code; PKCE supported).
            return WearableOAuthConfig(
                authorizeURL: URL(string: "https://cloud.ouraring.com/oauth/authorize")!,
                tokenURL: URL(string: "https://api.ouraring.com/oauth/token")!,
                clientID: clientID(for: provider),
                scopes: ["daily", "heartrate", "personal", "spo2"],
                redirectURI: redirect,
                extraAuthorizeItems: []
            )
        case .whoop:
            // Whoop Developer Platform OAuth2 (Authorization Code).
            return WearableOAuthConfig(
                authorizeURL: URL(string: "https://api.prod.whoop.com/oauth/oauth2/auth")!,
                tokenURL: URL(string: "https://api.prod.whoop.com/oauth/oauth2/token")!,
                clientID: clientID(for: provider),
                scopes: [
                    "read:recovery",
                    "read:cycles",
                    "read:sleep",
                    "read:workout",
                    "offline",
                ],
                redirectURI: redirect,
                extraAuthorizeItems: []
            )
        case .garmin:
            // Garmin Health API is OAuth 1.0a; our PKCE authenticator can't drive it.
            // Config is a placeholder so `isFlowSupported` keeps it honestly unavailable.
            return WearableOAuthConfig(
                authorizeURL: URL(string: "https://connect.garmin.com/oauthConfirm")!,
                tokenURL: URL(string: "https://connectapi.garmin.com/oauth-service/oauth/access_token")!,
                clientID: clientID(for: provider),
                scopes: [],
                redirectURI: redirect,
                extraAuthorizeItems: []
            )
        }
    }

    /// The authorize URL with PKCE + state, ready to hand to the web auth session.
    func authorizeRequestURL(pkce: PKCEChallenge, state: String) -> URL {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method),
            URLQueryItem(name: "state", value: state),
        ]
        items.append(contentsOf: extraAuthorizeItems)
        components.queryItems = items
        return components.url!
    }
}
