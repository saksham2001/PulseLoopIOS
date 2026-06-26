import Foundation

/// Sakana-style **multi-agent router**: instead of one generalist model answering
/// every turn, a fast, deterministic classifier picks the best *specialist* for the
/// turn. The chosen role carries a concrete model slug, a user-facing label, and a
/// short prompt hint that shapes tone/depth without weakening the strict-JSON output
/// contract. The orchestrator runs the existing tool loop on the routed model via its
/// `modelOverride` seam — one model per turn (route, don't ensemble) so cost/latency
/// stay ~1x.
///
/// Heuristic-first by design: no extra LLM call to classify, so routing adds no
/// latency. Anything ambiguous falls back to the generalist, which is the
/// reliability anchor (`openai/gpt-4o-mini`: best at tools + structured JSON).
enum AgentRole: String, CaseIterable, Sendable {
    /// Default. Chat, tool calling, reliable structured JSON. Safe fallback.
    case generalist
    /// Planning / deep reasoning (Nemotron). Needs reasoning-token handling.
    case strategist
    /// Long-context, multi-source research synthesis (MiniMax).
    case researcher
    /// Image/label understanding. Must be multimodal.
    case vision

    /// User-facing name shown in the trace ("Routing to Strategist · …").
    var label: String {
        switch self {
        case .generalist: return "Generalist"
        case .strategist: return "Strategist"
        case .researcher: return "Researcher"
        case .vision: return "Vision"
        }
    }

    /// SF Symbol representing the role in the trace strip (no emoji — design system).
    var symbolName: String {
        switch self {
        case .generalist: return "bubble.left.and.bubble.right"
        case .strategist: return "brain"
        case .researcher: return "magnifyingglass"
        case .vision: return "eye"
        }
    }

    /// True for specialists that require `detailed thinking on` and can emit
    /// reasoning tokens that must be stripped before JSON parsing (T3).
    var needsDetailedThinking: Bool { self == .strategist }

    /// Resolve the concrete OpenRouter slug for this role, honoring the user's
    /// per-tier overrides and tool-capable coercion (the loop depends on tools).
    var modelSlug: String {
        switch self {
        case .generalist:
            // The generalist must produce strict JSON every turn. If the user's
            // stored smart-tier slug is one that loops on JSON-apology replies
            // (e.g. Gemini Flash), use the reliability anchor instead — the agent
            // loop's structured-output contract takes priority over the picker.
            let slug = AIModel.smart.toolCapableResolvedSlug
            return AIModel.jsonUnreliableSlugs.contains(slug) ? AIModel.jsonReliableAnchor : slug
        case .strategist:
            return AgentRouter.resolvedSlug(forKey: "agentRole.strategist",
                                            default: AgentRouter.strategistDefault)
        case .researcher:
            return AgentRouter.resolvedSlug(forKey: "agentRole.researcher",
                                            default: AgentRouter.researcherDefault)
        case .vision:
            return AIModel.vision.toolCapableResolvedSlug
        }
    }

    /// A short directive appended to the system prompt to shape the specialist's
    /// behavior. Augments, never replaces, the base prompt; must not weaken the
    /// single-JSON output contract.
    var promptHint: String {
        switch self {
        case .generalist:
            return ""
        case .strategist:
            return "Routing note: you are acting as the Strategist. Think rigorously and plan first — decompose the problem, weigh trade-offs, and structure a clear, reasoned answer. Be decisive, not verbose. Still output exactly one JSON object per the schema."
        case .researcher:
            return "Routing note: you are acting as the Researcher. Search the live web for anything external or current, gather from multiple sources, and synthesize a grounded answer with citations. Prefer fresh, well-attributed facts over memory. Still output exactly one JSON object per the schema."
        case .vision:
            return "Routing note: you are acting as Vision. Read the attached image carefully and ground your answer in what you actually see. Still output exactly one JSON object per the schema."
        }
    }
}

/// The dispatcher. `route(...)` is pure and unit-tested: same inputs → same role.
enum AgentRouter {
    /// Default specialist slugs (verified on OpenRouter to support tools +
    /// structured output). Treated as defaults — the user can override per role.
    static let strategistDefault = "nvidia/nemotron-3-super-120b-a12b"
    static let researcherDefault = "minimax/minimax-m2"

    /// `UserDefaults` key for the routing master switch (default ON).
    static let routingEnabledKey = "agentRouting.enabled"

    /// Whether multi-agent routing is on. Default ON; off ⇒ generalist-only.
    static var routingEnabled: Bool {
        UserDefaults.standard.object(forKey: routingEnabledKey) as? Bool ?? true
    }

    static func resolvedSlug(forKey key: String, default fallback: String) -> String {
        let stored = UserDefaults.standard.string(forKey: key)
        if let stored, !stored.isEmpty { return stored }
        return fallback
    }

    /// `UserDefaults` key for per-role "auto" model selection (registry + feedback
    /// weighted). Default ON — the router picks the best available model for the role.
    static let autoModelKey = "agentRouting.autoModel"

    static var autoModelEnabled: Bool {
        UserDefaults.standard.object(forKey: autoModelKey) as? Bool ?? true
    }

    /// Whether the user pinned an explicit model for a role (per-role override or, for
    /// the generalist, a non-default smart-tier pick). When true, auto mode steps aside.
    static func hasExplicitOverride(for role: AgentRole) -> Bool {
        switch role {
        case .generalist:
            let stored = UserDefaults.standard.string(forKey: AIModel.smart.storageKey)
            return (stored?.isEmpty == false) && stored != AIModel.smart.defaultSlug
        case .strategist:
            return UserDefaults.standard.string(forKey: "agentRole.strategist")?.isEmpty == false
        case .researcher:
            return UserDefaults.standard.string(forKey: "agentRole.researcher")?.isEmpty == false
        case .vision:
            let stored = UserDefaults.standard.string(forKey: AIModel.vision.storageKey)
            return (stored?.isEmpty == false) && stored != AIModel.vision.defaultSlug
        }
    }

    /// Resolve the concrete model slug for a role. Honors (in order):
    /// 1. an explicit user override (per-role or per-tier) — always wins;
    /// 2. auto mode: the best registry candidate, feedback-weighted by `stats`;
    /// 3. the role's static default (`AgentRole.modelSlug`).
    /// The generalist's reliability-anchor coercion is always applied last so the
    /// strict-JSON contract can never be broken by a ranking choice.
    static func bestModel(for role: AgentRole, stats: [String: ModelOutcomeStats] = [:]) -> String {
        if hasExplicitOverride(for: role) || !autoModelEnabled {
            return role.modelSlug
        }
        let candidates = ModelRegistry.candidates(for: role)
        guard let picked = ModelRanking.best(candidates: candidates, stats: stats) else {
            return role.modelSlug
        }
        // Defense in depth: the generalist must never run an unreliable-JSON model.
        if role == .generalist, AIModel.jsonUnreliableSlugs.contains(picked) {
            return AIModel.jsonReliableAnchor
        }
        return picked
    }

    /// Why a turn routed where it did, for the transparency strip ("Reasoning task →
    /// Nemotron 3 Super"). Pure and presentational.
    static func routingRationale(role: AgentRole, slug: String, autoPicked: Bool) -> String {
        let task: String
        switch role {
        case .generalist: task = "General chat"
        case .strategist: task = "Reasoning task"
        case .researcher: task = "Research task"
        case .vision: task = "Image task"
        }
        let how = autoPicked ? "best model" : "your model"
        return "\(task) → \(how): \(shortModelName(slug))"
    }

    /// A compact, human-readable model name for the trace ("Nemotron 3 Super").
    /// Backed by the capability registry, falling back to the bare slug component.
    static func shortModelName(_ slug: String) -> String {
        ModelRegistry.displayName(for: slug)
    }

    /// Classify a turn → the best specialist role. Pure: depends only on the
    /// arguments and the routing toggle. Order matters: vision (hard) → routing
    /// gate → reasoning → research → generalist (safe default).
    static func route(userText: String, hasImage: Bool, recentMessages: [String] = []) -> AgentRole {
        // A photo turn must use the multimodal model regardless of routing/text.
        if hasImage { return .vision }

        // When routing is off, everything (non-photo) goes to the generalist —
        // exactly the pre-multi-agent behavior.
        guard routingEnabled else { return .generalist }

        let text = userText.lowercased()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .generalist
        }

        if matchesResearch(text) { return .researcher }
        if matchesReasoning(text) { return .strategist }
        return .generalist
    }

    // MARK: - Heuristics

    /// Research intent: current/external facts, multi-source lookups, comparisons of
    /// real-world entities — best handled by the long-context Researcher with search.
    private static func matchesResearch(_ text: String) -> Bool {
        let keywords = [
            "latest", "news", "today", "this week", "right now", "current",
            "find sources", "research", "look up", "search for", "who is",
            "what happened", "recent", "best ", "top ", "cheapest", "reviews",
            "price of", "how much does", "deals", "trending", "up to date",
            "according to", "cite", "sources",
            // Supplement / peptide / longevity questions are research-grade: they
            // want a grounded, cited answer from the product DB + web, not a guess
            // or a flat refusal. Route them to the Researcher so it looks them up.
            "peptide", "peptides", "supplement", "supplements", "what should i take",
            "should i take", "longevity", "live longer", "nootropic", "stack",
            "dosage", "dose of", "is it safe to take", "what helps with",
        ]
        return keywords.contains { text.contains($0) }
    }

    /// Reasoning/planning intent: strategy, analysis, multi-step plans, "why",
    /// trade-offs — best handled by the Strategist (Nemotron).
    private static func matchesReasoning(_ text: String) -> Bool {
        let keywords = [
            "plan", "strategy", "strategize", "step by step", "step-by-step",
            "break down", "analyze", "analyse", "reason", "think through",
            "trade-off", "tradeoff", "tradeoffs", "pros and cons", "compare",
            "evaluate", "design a", "architect", "optimize", "roadmap",
            "prioritize", "decide between", "why does", "why is", "why are",
            "explain why", "what's the best approach", "how should i",
        ]
        if keywords.contains(where: { text.contains($0) }) { return true }
        // Long, multi-part asks lean strategist even without a keyword.
        let wordCount = text.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
        let parts = text.filter { $0 == "?" || $0 == ";" }.count
        return wordCount >= 45 || parts >= 3
    }
}
