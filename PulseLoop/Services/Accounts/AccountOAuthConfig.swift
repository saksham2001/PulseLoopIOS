import Foundation

/// Static OAuth2 endpoint + scope configuration per **account** provider. Client
/// IDs are read from Info.plist (`GMAIL_CLIENT_ID`, `SLACK_CLIENT_ID`, …) so secrets
/// aren't hard-coded; a missing/placeholder id makes the provider "needs
/// configuration". Mirrors `WearableOAuthConfig`. Apple Calendar is local (EventKit)
/// and is intentionally NOT represented here — it's gated on `EKEventStore`
/// authorization, not a client id.
struct AccountOAuthConfig {
    let authorizeURL: URL
    let tokenURL: URL
    let clientID: String
    let scopes: [String]
    let redirectURI: String
    let extraAuthorizeItems: [URLQueryItem]

    static let callbackScheme = "pulseloop"

    static func redirectURI(for provider: AccountProvider) -> String {
        "\(callbackScheme)://oauth-callback/\(provider.rawValue)"
    }

    /// Account providers that authenticate over OAuth2 with our PKCE authenticator.
    /// (Apple Calendar uses EventKit, and Messages/Bank/wearable cases aren't account
    /// connectors here, so they're excluded.)
    static let oauthProviders: [AccountProvider] = [.gmail, .googleCalendar, .slack, .notion, .todoist]

    static func clientIDKey(for provider: AccountProvider) -> String? {
        switch provider {
        case .gmail: return "GMAIL_CLIENT_ID"
        case .googleCalendar: return "GOOGLE_CALENDAR_CLIENT_ID"
        case .slack: return "SLACK_CLIENT_ID"
        case .notion: return "NOTION_CLIENT_ID"
        case .todoist: return "TODOIST_CLIENT_ID"
        default: return nil
        }
    }

    static func clientID(for provider: AccountProvider) -> String {
        guard let key = clientIDKey(for: provider) else { return "" }
        let raw = (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether this provider authenticates locally (EventKit) instead of OAuth.
    static func isLocal(_ provider: AccountProvider) -> Bool { provider == .appleCalendar }

    /// True when a real (non-placeholder) client id is configured for this OAuth provider.
    static func isConfigured(_ provider: AccountProvider) -> Bool {
        guard oauthProviders.contains(provider) else { return false }
        let id = clientID(for: provider)
        return !id.isEmpty && !id.hasPrefix("YOUR_") && !id.hasPrefix("REPLACE") && id != "REPLACE_ME"
    }

    static func config(for provider: AccountProvider) -> AccountOAuthConfig? {
        let redirect = redirectURI(for: provider)
        switch provider {
        case .gmail:
            return AccountOAuthConfig(
                authorizeURL: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
                tokenURL: URL(string: "https://oauth2.googleapis.com/token")!,
                clientID: clientID(for: provider),
                scopes: ["https://www.googleapis.com/auth/gmail.readonly"],
                redirectURI: redirect,
                extraAuthorizeItems: [
                    URLQueryItem(name: "access_type", value: "offline"),
                    URLQueryItem(name: "prompt", value: "consent"),
                ]
            )
        case .googleCalendar:
            return AccountOAuthConfig(
                authorizeURL: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
                tokenURL: URL(string: "https://oauth2.googleapis.com/token")!,
                clientID: clientID(for: provider),
                scopes: ["https://www.googleapis.com/auth/calendar.readonly"],
                redirectURI: redirect,
                extraAuthorizeItems: [
                    URLQueryItem(name: "access_type", value: "offline"),
                    URLQueryItem(name: "prompt", value: "consent"),
                ]
            )
        case .slack:
            return AccountOAuthConfig(
                authorizeURL: URL(string: "https://slack.com/oauth/v2/authorize")!,
                tokenURL: URL(string: "https://slack.com/api/oauth.v2.access")!,
                clientID: clientID(for: provider),
                // Read-only user scopes; no chat:write so we can never post.
                scopes: [],
                redirectURI: redirect,
                extraAuthorizeItems: [
                    URLQueryItem(name: "user_scope", value: "channels:history,im:history,users:read"),
                ]
            )
        case .notion:
            return AccountOAuthConfig(
                authorizeURL: URL(string: "https://api.notion.com/v1/oauth/authorize")!,
                tokenURL: URL(string: "https://api.notion.com/v1/oauth/token")!,
                clientID: clientID(for: provider),
                scopes: [],
                redirectURI: redirect,
                extraAuthorizeItems: [URLQueryItem(name: "owner", value: "user")]
            )
        case .todoist:
            return AccountOAuthConfig(
                authorizeURL: URL(string: "https://todoist.com/oauth/authorize")!,
                tokenURL: URL(string: "https://todoist.com/oauth/access_token")!,
                clientID: clientID(for: provider),
                scopes: ["data:read_write"],
                redirectURI: redirect,
                extraAuthorizeItems: []
            )
        default:
            return nil
        }
    }

    func authorizeRequestURL(pkce: PKCEChallenge, state: String) -> URL {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: pkce.method),
            URLQueryItem(name: "state", value: state),
        ]
        if !scopes.isEmpty {
            items.append(URLQueryItem(name: "scope", value: scopes.joined(separator: " ")))
        }
        items.append(contentsOf: extraAuthorizeItems)
        components.queryItems = items
        return components.url!
    }
}
