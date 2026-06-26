import Foundation

/// Resolves "can the real coach run, and which tool classes are allowed" from
/// the user's settings plus whether a key is actually present. Mirrors the web
/// app's `settings.coach_enabled` gate, extended with per-class tool toggles.
struct CoachFeatureFlags {
    let settings: CoachSettings
    let hasAPIKey: Bool

    /// User-facing master switch  -  when off, the coach tab, summaries and
    /// notifications are all hidden. This is the gate the UI checks; the
    /// `coachEnabled` flag below additionally factors in provider/key state.
    var masterEnabled: Bool { settings.coachMasterEnabled }

    /// True when the real (LLM-backed) coach should run. Otherwise the
    /// orchestrator falls back to a deterministic scripted response.
    ///
    /// Two shipping paths qualify:
    /// - **Backend proxy**: the server holds the key, so no on-device key is needed —
    ///   only the master switch plus a usable proxy URL.
    /// - **BYO key (default / dev)**: master switch plus an available OpenRouter key
    ///   (`hasAPIKey`), since the coach calls the provider directly.
    var coachEnabled: Bool {
        guard settings.coachMasterEnabled else { return false }
        if settings.providerMode == .backendProxy {
            return backendProxyConfigured
        }
        if settings.providerMode == .bedrock {
            // Bedrock runs when its own creds are configured, OR when a fallback
            // transport exists (on-device key / paired proxy) — see makeClient,
            // which degrades a misconfigured bedrock selection to a working path.
            return bedrockConfigured || hasAPIKey || Self.pairedProxyAvailable
        }
        // Even in BYO-key mode, the coach can run when the device is paired to the
        // PulseLoop backend (the server holds the OpenRouter key). This is the
        // zero-config path: pair the device and AI just works, no on-device key.
        return hasAPIKey || Self.pairedProxyAvailable
    }

    /// True when the backend proxy has a usable base URL configured.
    var backendProxyConfigured: Bool {
        if let url = URL(string: settings.backendProxyURL.trimmingCharacters(in: .whitespacesAndNewlines)),
           url.scheme == "https" || url.scheme == "http" {
            return true
        }
        return Self.pairedProxyAvailable
    }

    /// The PulseLoop web backend URL from `PULSELOOP_WEB_URL`, when valid for use.
    static var appWebBaseURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "PULSELOOP_WEB_URL") as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), let host = url.host else { return nil }
        let isLocal = host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".local")
        #if DEBUG
        return url
        #else
        return isLocal ? nil : url
        #endif
    }

    /// True when the device is paired (token present) and the web URL is set, so
    /// the coach can route through the backend proxy with the server-held key.
    static var pairedProxyAvailable: Bool {
        guard appWebBaseURL != nil else { return false }
        let token = (try? CloudSyncKeychainStore().readKey()) ?? nil
        return (token?.isEmpty == false)
    }

    /// True when AWS Bedrock credentials + region + model are all present.
    var bedrockConfigured: Bool {
        guard BedrockCredentialsStore().hasCredentials else { return false }
        let region = settings.bedrockRegion.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = settings.bedrockModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return !region.isEmpty && !model.isEmpty
    }

    var webSearchEnabled: Bool { settings.enableWebSearch }
    var writeToolsEnabled: Bool { settings.enableWriteTools }
    var liveMeasurementsEnabled: Bool { settings.enableLiveMeasurements }
    var subAppBuilderEnabled: Bool { settings.enableSubAppBuilder }
    /// Platform control: AI can manage modules, install designed sub-apps, and
    /// create tasks/notes. Requires the coach to actually be running (LLM-backed).
    var platformControlEnabled: Bool { settings.enablePlatformControl }

    /// Media generation (muapi.ai) is available when enabled in settings AND a
    /// muapi key is present in the Keychain.
    var mediaGenerationEnabled: Bool {
        settings.enableMediaGeneration && MuapiKeychainStore().hasKey
    }

    var maxToolCalls: Int { max(1, settings.maxToolCalls) }
    var maxRounds: Int { max(1, settings.maxRounds) }
    /// The OpenRouter model slug the coach turn should use (user-selected smart
    /// tier, falling back to the tier default). Coerced to a tool-capable model
    /// since the coach agent loop depends on function calling.
    var model: String { AIModel.smart.toolCapableResolvedSlug }

    /// One-line status for the Settings UI.
    var statusLine: String {
        if !settings.coachMasterEnabled { return "Off  -  turn on AI Assistant to enable." }
        if settings.providerMode == .backendProxy {
            return backendProxyConfigured
                ? "Ready · PulseLoop backend"
                : "Set the PulseLoop backend URL to enable AI."
        }
        return hasAPIKey
            ? "Ready · \(AIModel.smart.resolvedSlug)"
            : "Set an OpenRouter key to enable AI."
    }
}
