import Foundation

/// Where the coach's "brain" runs.
/// - `offlineStub`: scripted replies only, no network, no credits.
/// - `userOpenAIKey`: BYO-key direct to OpenAI; credits metered locally (transitional).
/// - `backendProxy`: iOS → PulseLoop server → OpenAI. The server holds the key and is
///   the **authoritative** credit ledger; the client meters optimistically and trusts
///   the server's balance. This is the enforcement seam (roadmap E3).
/// - `bedrock`: BYO AWS IAM credentials direct to Anthropic Claude on AWS Bedrock.
///   Credentials live in the Keychain; credits are metered locally (transitional,
///   like `userOpenAIKey`). The client translates the OpenAI Responses wire format
///   to/from the Anthropic Messages format and signs requests with SigV4.
enum CoachProviderMode: String, Codable, CaseIterable, Identifiable {
    case offlineStub
    case userOpenAIKey
    case backendProxy
    case bedrock

    var id: String { rawValue }

    var label: String {
        switch self {
        case .offlineStub: return "Offline"
        case .userOpenAIKey: return "OpenAI (your key)"
        case .backendProxy: return "Backend proxy"
        case .bedrock: return "AWS Bedrock (Claude)"
        }
    }

    /// The shipping provider matrix (single source of truth — roadmap B1).
    ///
    /// - `backendProxy` + `userOpenAIKey` are the two **shipping** paths for a paid
    ///   release: the metered server proxy and BYO-key.
    /// - `offlineStub` is a deterministic, network-free dev/test path and must never
    ///   be offered as a user-selectable provider in a release build.
    /// - `bedrock` is experimental (BYO AWS IAM) and is not part of the launch matrix;
    ///   it is gated behind DEBUG until/unless it ships.
    ///
    /// Any provider picker MUST iterate `selectableModes` (not `allCases`) so the UI
    /// can only ever offer a path the build actually supports.
    var isShippable: Bool {
        switch self {
        case .userOpenAIKey, .backendProxy:
            return true
        case .offlineStub, .bedrock:
            return false
        }
    }

    /// Provider modes a user may pick in this build. Release builds expose only the
    /// shipping matrix; DEBUG builds additionally expose the dev/experimental modes so
    /// they remain testable without ever leaking into a shipped UI.
    static var selectableModes: [CoachProviderMode] {
        #if DEBUG
        return allCases
        #else
        return allCases.filter { $0.isShippable }
        #endif
    }
}

/// Preset OpenAI model choices. The stored `CoachSettings.model` is a free
/// string (so a new model can be typed/served without a code change); these are
/// just the curated picks surfaced in Settings.
enum CoachModel: String, CaseIterable, Identifiable {
    case gpt54mini = "gpt-5.4-mini"
    case gpt54 = "gpt-5.4"
    case gpt55 = "gpt-5.5"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gpt54mini: return "gpt-5.4-mini"
        case .gpt54: return "gpt-5.4"
        case .gpt55: return "gpt-5.5"
        }
    }

    var blurb: String {
        switch self {
        case .gpt54mini: return "Lower cost & latency"
        case .gpt54: return "Balanced (default)"
        case .gpt55: return "Best reasoning"
        }
    }
}

/// AI coach personality modes — changes tone and communication style.
enum CoachPersonality: String, Codable, CaseIterable, Identifiable {
    case friend
    case dataNerd
    case guardian
    case commander

    var id: String { rawValue }

    var label: String {
        switch self {
        case .friend: return "Friend"
        case .dataNerd: return "Data Nerd"
        case .guardian: return "Guardian"
        case .commander: return "Commander"
        }
    }

    var iconSystemName: String {
        switch self {
        case .friend: return "heart.fill"
        case .dataNerd: return "brain.head.profile"
        case .guardian: return "shield.fill"
        case .commander: return "flame.fill"
        }
    }

    var traits: [String] {
        switch self {
        case .friend: return ["Supportive", "Positive", "Caring"]
        case .dataNerd: return ["Curious", "Insightful", "Analytical"]
        case .guardian: return ["Protective", "Cautious", "Steady"]
        case .commander: return ["Focused", "Decisive", "Action-Driven"]
        }
    }

    var description: String {
        switch self {
        case .friend: return "Focuses on how you're feeling and helps you stay balanced. Offers gentle guidance, celebrates small wins, and supports healthy habits without pressure."
        case .dataNerd: return "Looks closely at your data to uncover patterns and trends. Explains what's happening in a clear way so you can better understand how your habits affect your health."
        case .guardian: return "Keeps an eye on your wellbeing and helps you avoid pushing too far. Points out risks, encourages balance, and supports choices that protect your long-term health."
        case .commander: return "Cuts through the noise and helps you move forward. Highlights what matters most and gives clear, direct guidance so you can stay on track and keep momentum."
        }
    }

    var promptModifier: String {
        switch self {
        case .friend: return """
            Personality: Supportive Friend.
            Tone: Warm, encouraging, empathetic. Use casual language. Celebrate wins, no matter how small. When giving feedback, lead with positives. Avoid being preachy or clinical. Make the user feel supported.
            Style: Use phrases like "You're doing great!", "That's a solid day", "No worries, tomorrow's a fresh start". Keep it conversational.
            """
        case .dataNerd: return """
            Personality: Data Nerd.
            Tone: Curious, analytical, precise. Love numbers and patterns. Explain insights with specifics (percentages, comparisons, correlations). Show excitement about interesting data points.
            Style: Use phrases like "Here's what's interesting...", "I'm seeing a pattern...", "The data suggests...", "Your 7-day trend shows...". Be nerdy but accessible.
            """
        case .guardian: return """
            Personality: Guardian.
            Tone: Protective, measured, calm. Prioritize long-term health over short-term gains. Flag potential risks proactively. Encourage rest and recovery.
            Style: Use phrases like "Take it steady today", "Protect your energy", "Let's not overdo it", "Your body needs recovery time". Be the voice of balance.
            """
        case .commander: return """
            Personality: Commander.
            Tone: Direct, decisive, no-nonsense. Cut through excuses. Focus on what matters. Give clear action items. Be motivating without being aggressive.
            Style: Use phrases like "Focus up!", "Here's your priority today", "No excuses — let's go", "The data is clear, here's what to do". Be the accountability partner.
            """
        }
    }
}

/// User-tunable coach configuration, persisted as JSON in `UserDefaults`.
struct CoachSettings: Codable, Equatable {
    /// Master switch for all AI Assistant features (tab, summaries, notifications).
    /// On by default so the assistant works out of the box (key is provided via
    /// Info.plist / paired backend); users who only want metrics can turn it off.
    var coachMasterEnabled: Bool = true
    var providerMode: CoachProviderMode = .userOpenAIKey
    /// Base URL of the PulseLoop AI backend proxy (used when `providerMode` is
    /// `.backendProxy`). The server holds the OpenAI key and enforces credits
    /// server-side. Empty until a build configures it.
    var backendProxyURL: String = ""
    /// AWS region for the Bedrock provider (used when `providerMode` is `.bedrock`).
    /// Not a secret; the IAM credentials live in the Keychain.
    var bedrockRegion: String = "us-east-1"
    /// Bedrock model id / inference profile for the `.bedrock` provider. Defaults
    /// to the latest Claude Opus cross-region inference profile. User-editable so a
    /// new model can be used without a code change.
    var bedrockModelID: String = "us.anthropic.claude-opus-4-1-20250805-v1:0"
    /// Default matches the web app; user-configurable (never hard-coded in the client).
    var model: String = CoachModel.gpt54.rawValue
    /// Optional reasoning effort hint ("low"/"medium"/"high") when the model supports it.
    var reasoningEffort: String? = nil
    /// On by default: the assistant has broad, "unlimited" web search so it can
    /// look up flights, hotels/Airbnbs, events, restaurants, prices, places, and
    /// any real-world/general-knowledge question instead of guessing.
    var enableWebSearch: Bool = true
    /// On by default so the assistant can actually organize the user's life —
    /// create tasks/notes/trips, log entries, etc. Reversible writes apply
    /// immediately; destructive ones still require a Confirm/Cancel card.
    var enableWriteTools: Bool = true
    var enableLiveMeasurements: Bool = false
    /// Phase D — lets the coach author/refine declarative sub-apps via the
    /// `generate_subapp_spec` / `refine_subapp_spec` tools (AI Sub-App Builder).
    var enableSubAppBuilder: Bool = false
    /// Lets the AI command palette manage the whole app: enable/disable modules,
    /// install designed sub-apps live, and create tasks/notes. Reversible changes
    /// apply immediately; destructive ones (disabling/uninstalling) ask first.
    var enablePlatformControl: Bool = true
    /// Multifunction track — lets the coach generate media (images/video) in-chat
    /// via muapi.ai. Only effective when a muapi key is present.
    var enableMediaGeneration: Bool = true
    /// When true, muapi calls run in sandbox mode (returns example media, no spend).
    /// Defaults on so first-run + tests never cost real credits; users turn it off
    /// to generate for real.
    var muapiSandbox: Bool = true
    var maxToolCalls: Int = 8
    var maxRounds: Int = 4
    // Milestone D  -  automated daily check-in notifications.
    var notificationsEnabled: Bool = false
    var morningHour: Int = 8
    var eveningHour: Int = 19
    // Personality
    var personality: CoachPersonality = .dataNerd
    // Onboarding
    var hasCompletedOnboarding: Bool = false
    var primaryGoal: String = ""

    static let `default` = CoachSettings()

    init() {}

    /// Tolerant decode: missing keys (older stored settings, new fields) fall back
    /// to defaults instead of failing the whole decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CoachSettings.default
        coachMasterEnabled = try c.decodeIfPresent(Bool.self, forKey: .coachMasterEnabled) ?? d.coachMasterEnabled
        providerMode = try c.decodeIfPresent(CoachProviderMode.self, forKey: .providerMode) ?? d.providerMode
        backendProxyURL = try c.decodeIfPresent(String.self, forKey: .backendProxyURL) ?? d.backendProxyURL
        bedrockRegion = try c.decodeIfPresent(String.self, forKey: .bedrockRegion) ?? d.bedrockRegion
        bedrockModelID = try c.decodeIfPresent(String.self, forKey: .bedrockModelID) ?? d.bedrockModelID
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        reasoningEffort = try c.decodeIfPresent(String.self, forKey: .reasoningEffort)
        enableWebSearch = try c.decodeIfPresent(Bool.self, forKey: .enableWebSearch) ?? d.enableWebSearch
        enableWriteTools = try c.decodeIfPresent(Bool.self, forKey: .enableWriteTools) ?? d.enableWriteTools
        enableLiveMeasurements = try c.decodeIfPresent(Bool.self, forKey: .enableLiveMeasurements) ?? d.enableLiveMeasurements
        enableSubAppBuilder = try c.decodeIfPresent(Bool.self, forKey: .enableSubAppBuilder) ?? d.enableSubAppBuilder
        enablePlatformControl = try c.decodeIfPresent(Bool.self, forKey: .enablePlatformControl) ?? d.enablePlatformControl
        enableMediaGeneration = try c.decodeIfPresent(Bool.self, forKey: .enableMediaGeneration) ?? d.enableMediaGeneration
        muapiSandbox = try c.decodeIfPresent(Bool.self, forKey: .muapiSandbox) ?? d.muapiSandbox
        maxToolCalls = try c.decodeIfPresent(Int.self, forKey: .maxToolCalls) ?? d.maxToolCalls
        maxRounds = try c.decodeIfPresent(Int.self, forKey: .maxRounds) ?? d.maxRounds
        notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? d.notificationsEnabled
        morningHour = try c.decodeIfPresent(Int.self, forKey: .morningHour) ?? d.morningHour
        eveningHour = try c.decodeIfPresent(Int.self, forKey: .eveningHour) ?? d.eveningHour
        personality = try c.decodeIfPresent(CoachPersonality.self, forKey: .personality) ?? d.personality
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? d.hasCompletedOnboarding
        primaryGoal = try c.decodeIfPresent(String.self, forKey: .primaryGoal) ?? d.primaryGoal
    }
}

/// Observable, UserDefaults-backed store for `CoachSettings`. Mutating `settings`
/// persists immediately. A shared instance keeps Settings and the coach in sync.
@MainActor
@Observable
final class CoachSettingsStore {
    static let shared = CoachSettingsStore()

    private static let storageKey = "pulseloop.coach.settings.v1"
    private let defaults: UserDefaults

    var settings: CoachSettings {
        didSet { persist() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(CoachSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = .default
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
