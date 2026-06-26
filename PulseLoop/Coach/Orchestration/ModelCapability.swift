import Foundation

// MARK: - Model capability registry (Life OS T4)
//
// A declarative description of what each candidate model can do, so routing can pick
// the *best available* model for a role/task from data rather than scattered
// conditionals. This is the single source of truth for capability questions
// (tools? vision? reliable JSON? how strong? how cheap?) layered on top of the
// existing `AIModel` tiers — it never changes the reliability-anchor semantics
// (`AIModel.jsonReliableAnchor`, `jsonUnreliableSlugs`, `toolIncompatibleSlugs`).

/// Relative quality/cost class for tie-breaking and routing preference. Higher
/// `quality` ⇒ stronger; higher `costRank` ⇒ more expensive (prefer lower when tied).
struct ModelCapability: Hashable, Sendable {
    let slug: String
    let displayName: String
    /// Can the model reliably call functions/tools? The Coach agent loop requires it.
    let supportsTools: Bool
    /// Can the model accept image input?
    let supportsVision: Bool
    /// Does it reliably emit the strict single-JSON `coach_response` envelope?
    let jsonReliable: Bool
    /// Coarse capability strength (0...100), used as a default-quality prior before
    /// any feedback signal exists.
    let quality: Int
    /// Coarse relative cost (0 cheapest ... 100 priciest); lower wins ties.
    let costRank: Int
}

/// The known model catalog. Seeded to stay consistent with `AIModel` tiers and the
/// anchor/unreliable sets, and is refreshable at runtime (T4 catalog provider) — but
/// the bundled table guarantees routing always has candidates offline.
enum ModelRegistry {
    /// Built-in capability table. Slugs mirror `AIModel.options`.
    static let bundled: [ModelCapability] = [
        ModelCapability(slug: "openai/gpt-4o-mini", displayName: "GPT-4o mini",
                        supportsTools: true, supportsVision: true, jsonReliable: true, quality: 70, costRank: 10),
        ModelCapability(slug: "openai/gpt-5-mini", displayName: "GPT-5 mini",
                        supportsTools: true, supportsVision: true, jsonReliable: true, quality: 78, costRank: 20),
        ModelCapability(slug: "openai/gpt-5.5", displayName: "GPT-5.5",
                        supportsTools: true, supportsVision: true, jsonReliable: true, quality: 92, costRank: 70),
        ModelCapability(slug: "openai/gpt-5.5-pro", displayName: "GPT-5.5 Pro",
                        supportsTools: true, supportsVision: true, jsonReliable: true, quality: 96, costRank: 90),
        ModelCapability(slug: "anthropic/claude-haiku-4.5", displayName: "Claude Haiku 4.5",
                        supportsTools: true, supportsVision: true, jsonReliable: true, quality: 72, costRank: 18),
        ModelCapability(slug: "anthropic/claude-sonnet-4.5", displayName: "Claude Sonnet 4.5",
                        supportsTools: true, supportsVision: true, jsonReliable: true, quality: 88, costRank: 55),
        ModelCapability(slug: "anthropic/claude-sonnet-4.6", displayName: "Claude Sonnet 4.6",
                        supportsTools: true, supportsVision: true, jsonReliable: true, quality: 90, costRank: 58),
        ModelCapability(slug: "anthropic/claude-opus-4.8", displayName: "Claude Opus 4.8",
                        supportsTools: true, supportsVision: true, jsonReliable: true, quality: 97, costRank: 95),
        ModelCapability(slug: "google/gemini-2.5-flash", displayName: "Gemini 2.5 Flash",
                        supportsTools: true, supportsVision: true, jsonReliable: false, quality: 74, costRank: 8),
        ModelCapability(slug: "google/gemini-2.5-flash-lite", displayName: "Gemini 2.5 Flash Lite",
                        supportsTools: true, supportsVision: true, jsonReliable: false, quality: 64, costRank: 5),
        ModelCapability(slug: "google/gemini-3.1-pro-preview", displayName: "Gemini 3.1 Pro",
                        supportsTools: true, supportsVision: true, jsonReliable: true, quality: 91, costRank: 60),
        ModelCapability(slug: "google/gemini-3.1-flash-lite-preview", displayName: "Gemini 3.1 Flash Lite",
                        supportsTools: true, supportsVision: true, jsonReliable: true, quality: 68, costRank: 6),
        ModelCapability(slug: "z-ai/glm-4.6", displayName: "GLM-4.6",
                        supportsTools: true, supportsVision: false, jsonReliable: true, quality: 76, costRank: 12),
        ModelCapability(slug: "z-ai/glm-4.5-air", displayName: "GLM-4.5 Air",
                        supportsTools: true, supportsVision: false, jsonReliable: true, quality: 66, costRank: 7),
        ModelCapability(slug: "z-ai/glm-5.2", displayName: "GLM-5.2",
                        supportsTools: true, supportsVision: false, jsonReliable: true, quality: 89, costRank: 40),
        ModelCapability(slug: "nvidia/nemotron-3-super-120b-a12b", displayName: "Nemotron 3 Super",
                        supportsTools: true, supportsVision: false, jsonReliable: true, quality: 87, costRank: 35),
        ModelCapability(slug: "minimax/minimax-m2", displayName: "MiniMax M2",
                        supportsTools: true, supportsVision: false, jsonReliable: true, quality: 83, costRank: 22),
    ]

    /// Runtime-overridable catalog (refreshed by `ModelCatalogProvider`). Defaults to
    /// the bundled table; never empty.
    private static var live: [ModelCapability]?

    static var all: [ModelCapability] { live ?? bundled }

    /// Replace the live catalog (merging unknown bundled entries so we never lose a
    /// known-good candidate). No-op for an empty input.
    static func update(with capabilities: [ModelCapability]) {
        guard !capabilities.isEmpty else { return }
        var bySlug = Dictionary(uniqueKeysWithValues: bundled.map { ($0.slug, $0) })
        for cap in capabilities { bySlug[cap.slug] = cap }
        live = Array(bySlug.values)
    }

    static func capability(for slug: String) -> ModelCapability? {
        all.first { $0.slug == slug }
    }

    /// A friendly display name for a slug, falling back to the bare model component.
    static func displayName(for slug: String) -> String {
        capability(for: slug)?.displayName
            ?? slug.split(separator: "/").last.map(String.init)
            ?? slug
    }

    /// Candidate models appropriate for a routing role, honoring hard constraints:
    /// the agent loop needs tools; vision turns need a multimodal model; the
    /// generalist needs reliable JSON. Returns at least the role's anchor when the
    /// filter would otherwise be empty.
    static func candidates(for role: AgentRole) -> [ModelCapability] {
        let pool: [ModelCapability]
        switch role {
        case .vision:
            pool = all.filter { $0.supportsTools && $0.supportsVision }
        case .generalist:
            pool = all.filter { $0.supportsTools && $0.jsonReliable }
        case .strategist, .researcher:
            pool = all.filter { $0.supportsTools }
        }
        if pool.isEmpty, let anchor = capability(for: AIModel.jsonReliableAnchor) {
            return [anchor]
        }
        return pool
    }
}
