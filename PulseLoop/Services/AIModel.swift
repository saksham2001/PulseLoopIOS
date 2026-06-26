import Foundation
import SwiftUI

/// The four AI workloads in PulseLoop, each routed to the model best suited for it.
/// Call sites pick a *tier* rather than a hard-coded slug; the concrete OpenRouter
/// model is resolved at runtime (user override → tier default). This keeps model
/// selection in one place and lets the Settings picker swap models without touching
/// any feature code.
enum AIModel: String, CaseIterable, Identifiable {
    /// Streaming conversational Coach + anything needing good reasoning + tool use.
    case smart
    /// The many small, latency-sensitive structured-JSON extractors.
    case fast
    /// Image understanding (food photos, label scans). Must be multimodal.
    case vision
    /// Rare, high-value deep analysis (e.g. protocol interaction review).
    case reasoning

    var id: String { rawValue }

    /// Default OpenRouter slug for this tier. Chosen for PulseLoop's mix of
    /// frequent cheap JSON calls + a snappy multimodal Coach in a health domain.
    var defaultSlug: String {
        switch self {
        // GPT-4o-mini is the most consistent at producing valid structured JSON
        // *while* using tools — the assistant's agent loop depends on both, and
        // Gemini Flash was unreliable here (looped on "fixing JSON" apologies).
        case .smart: return "openai/gpt-4o-mini"
        case .fast: return "google/gemini-2.5-flash-lite"
        case .vision: return "openai/gpt-4o-mini"
        case .reasoning: return "anthropic/claude-sonnet-4.5"
        }
    }

    /// User-facing label for the Settings picker.
    var title: String {
        switch self {
        case .smart: return "Assistant & chat"
        case .fast: return "Quick tasks"
        case .vision: return "Photo & label scan"
        case .reasoning: return "Deep analysis"
        }
    }

    var subtitle: String {
        switch self {
        case .smart: return "Conversational assistant"
        case .fast: return "Fast structured suggestions"
        case .vision: return "Image understanding"
        case .reasoning: return "Careful, in-depth reasoning"
        }
    }

    /// Curated, vetted options the user can choose for this tier. Kept small and
    /// workload-appropriate (vision options are multimodal only). Slugs are current
    /// OpenRouter identifiers; OpenRouter rotates fast, so treat these as defaults.
    var options: [AIModelOption] {
        switch self {
        case .smart:
            // Coach turns require function/tool calling. Only list models that
            // actually support it on OpenRouter. (Gemma 3 ignores tools entirely,
            // which makes the agent loop fail — so it's intentionally excluded.)
            return [
                AIModelOption("openai/gpt-4o-mini", "GPT-4o mini"),
                AIModelOption("google/gemini-2.5-flash", "Gemini 2.5 Flash"),
                AIModelOption("google/gemini-3.1-pro-preview", "Gemini 3.1 Pro"),
                AIModelOption("z-ai/glm-4.6", "GLM-4.6 (value)"),
                AIModelOption("nvidia/nemotron-3-super-120b-a12b", "Nemotron 3 Super (reasoning)"),
                AIModelOption("minimax/minimax-m2", "MiniMax M2 (long-context agent)"),
                AIModelOption("anthropic/claude-sonnet-4.6", "Claude Sonnet 4.6"),
                AIModelOption("anthropic/claude-opus-4.8", "Claude Opus 4.8"),
                AIModelOption("openai/gpt-5.5", "GPT-5.5"),
                AIModelOption("openai/gpt-5-mini", "GPT-5 mini")
            ]
        case .fast:
            // Used for structured-JSON extractors; needs reliable response_format.
            return [
                AIModelOption("google/gemini-2.5-flash-lite", "Gemini 2.5 Flash Lite"),
                AIModelOption("google/gemini-3.1-flash-lite-preview", "Gemini 3.1 Flash Lite"),
                AIModelOption("anthropic/claude-haiku-4.5", "Claude Haiku 4.5"),
                AIModelOption("openai/gpt-5-mini", "GPT-5 mini"),
                AIModelOption("z-ai/glm-4.5-air", "GLM-4.5 Air")
            ]
        case .vision:
            return [
                AIModelOption("google/gemini-2.5-flash", "Gemini 2.5 Flash"),
                AIModelOption("google/gemini-3.1-pro-preview", "Gemini 3.1 Pro"),
                AIModelOption("anthropic/claude-sonnet-4.6", "Claude Sonnet 4.6"),
                AIModelOption("anthropic/claude-opus-4.8", "Claude Opus 4.8"),
                AIModelOption("openai/gpt-5.5", "GPT-5.5"),
                AIModelOption("openai/gpt-5-mini", "GPT-5 mini")
            ]
        case .reasoning:
            return [
                AIModelOption("anthropic/claude-sonnet-4.6", "Claude Sonnet 4.6"),
                AIModelOption("anthropic/claude-opus-4.8", "Claude Opus 4.8"),
                AIModelOption("openai/gpt-5.5-pro", "GPT-5.5 Pro"),
                AIModelOption("nvidia/nemotron-3-super-120b-a12b", "Nemotron 3 Super"),
                AIModelOption("google/gemini-3.1-pro-preview", "Gemini 3.1 Pro"),
                AIModelOption("z-ai/glm-5.2", "GLM-5.2")
            ]
        }
    }

    /// The slug to actually send: a stored user override if present and valid,
    /// otherwise the tier default.
    var resolvedSlug: String {
        let stored = UserDefaults.standard.string(forKey: storageKey)
        if let stored, !stored.isEmpty { return stored }
        return defaultSlug
    }

    /// Like `resolvedSlug`, but guaranteed to be a model that supports function /
    /// tool calling. The Coach agent loop is built on tools (it must call
    /// `get_today`, etc. to ground answers); a model that ignores tools returns
    /// prose the orchestrator can't parse and the turn fails with "I had trouble
    /// with that". If the user picked (or an old build persisted) a known
    /// tool-incompatible slug, coerce to a safe default instead of breaking.
    var toolCapableResolvedSlug: String {
        let slug = resolvedSlug
        if AIModel.toolIncompatibleSlugs.contains(slug) {
            return AIModel.smart.defaultSlug
        }
        return slug
    }

    /// OpenRouter slugs that do not support function/tool calling (or do so too
    /// unreliably for the agent loop). Selecting these for a tool-using tier
    /// would break the Coach, so they're coerced away at call time.
    static let toolIncompatibleSlugs: Set<String> = [
        "google/gemma-3-27b-it",
    ]

    /// The reliability anchor: the one slug we trust to produce valid structured
    /// JSON *while* using tools, every turn. Used as the generalist fallback and
    /// the recovery target when another model loops on JSON-apology replies.
    static let jsonReliableAnchor = "openai/gpt-4o-mini"

    /// Slugs that, in practice, fail to reliably emit the strict `coach_response`
    /// JSON envelope and instead loop on "sorry, I'll fix the JSON" meta-apologies.
    /// When one of these is the active generalist model and the turn can't be
    /// parsed, we recover on `jsonReliableAnchor` instead of surfacing the apology.
    static let jsonUnreliableSlugs: Set<String> = [
        "google/gemini-2.5-flash",
        "google/gemini-2.5-flash-lite",
    ]

    /// `@AppStorage`/`UserDefaults` key holding the user's chosen slug for this tier.
    var storageKey: String { "aiModel.\(rawValue)" }

    /// The display label for an option, appending "(recommended)" to the tier's
    /// default slug so the Settings picker flags the suggested choice. For the
    /// smart tier, the recommended option is the JSON-reliability anchor.
    func optionLabel(for option: AIModelOption) -> String {
        let recommended = (self == .smart) ? AIModel.jsonReliableAnchor : defaultSlug
        return option.slug == recommended ? "\(option.label) (recommended)" : option.label
    }
}

/// A selectable model option (OpenRouter slug + display label).
struct AIModelOption: Identifiable, Hashable {
    let slug: String
    let label: String
    var id: String { slug }
    init(_ slug: String, _ label: String) {
        self.slug = slug
        self.label = label
    }
}
