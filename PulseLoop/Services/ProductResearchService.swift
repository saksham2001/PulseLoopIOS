import Foundation

// MARK: - Product Research Service (the AI "Perplexity" tier)
//
// The final, highest-effort tier of the unified product search. When local
// catalogs and the live APIs (Open Food Facts / openFDA) miss or come back
// low-confidence, this asks the LLM to synthesize a COMPLETE, structured profile
// for the queried food / drug / supplement / vitamin / peptide and to cite the
// sources it relied on. The model is asked to ground its answer in real, public
// knowledge and to return citations — a Perplexity-style answer engine for the
// tracker.
//
// Output decodes into a typed `ResearchedProduct` (never free text the UI has to
// re-parse) and converts to `SupplementInfo` so it slots into the existing result
// pipeline. Every result carries `isAIGenerated = true` so the UI shows the
// "verify with a professional" disclaimer, plus the citations it returned.

/// Typed result of an AI research pass. Mirrors `SupplementInfo` plus provenance.
struct ResearchedProduct {
    let name: String
    let aliases: [String]
    let category: String          // medication | supplement | vitamin | peptide | food
    let defaultDose: String
    let iconSystemName: String    // SF Symbol (no emoji)
    let timing: String
    let benefit: String
    let mechanism: String
    let bestTimeReason: String
    let interactionNotes: String
    let pros: [String]
    let cons: [String]
    let citations: [String]
    /// 0–1 self-reported confidence; we clamp + floor it.
    let confidence: Double

    var asSupplementInfo: SupplementInfo {
        SupplementInfo(
            name: name,
            aliases: aliases.isEmpty ? [name.lowercased()] : aliases,
            category: category,
            defaultDose: defaultDose,
            emoji: iconSystemName,
            timing: timing,
            benefit: benefit,
            mechanism: mechanism,
            bestTimeReason: bestTimeReason,
            stackNotes: "AI-researched entry — verify with a healthcare professional before use",
            interactionNotes: interactionNotes,
            pros: pros,
            cons: cons
        )
    }
}

@MainActor
enum ProductResearchService {

    /// True when an AI research pass is possible (an OpenRouter key is configured).
    static var isAvailable: Bool { AIService.shared.hasAPIKey }

    /// Synthesize a structured profile for `query`. Returns `nil` when no key is
    /// configured, the network fails, or the model returns unusable output — callers
    /// must degrade gracefully (e.g. fall back to `AIProductInference`).
    ///
    /// `preferWebGrounding` requests OpenRouter's online/web plugin (the `:online`
    /// model suffix) so the answer is grounded in live web results with citations.
    /// If grounding is unavailable the model still answers from its own knowledge.
    static func research(query: String, preferWebGrounding: Bool = true) async -> ResearchedProduct? {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, isAvailable else { return nil }

        let system = """
        You are a meticulous health-product research engine for an app that tracks \
        foods, medications, supplements, vitamins, and peptides. Given a product or \
        ingredient name, produce ONE accurate, structured profile grounded in \
        established public knowledge. Prefer well-established facts; never invent \
        precise prescription dosing as medical advice — describe typical/label ranges \
        and defer to a professional. Cite the sources or references you relied on.

        Respond with ONLY a single JSON object, no markdown, matching exactly:
        {
          "name": string,                // canonical product/ingredient name
          "aliases": [string],           // lowercase alternate names/brands
          "category": string,            // one of: medication, supplement, vitamin, peptide, food
          "default_dose": string,        // typical dose or label serving, e.g. "5000 IU", "250 mcg"
          "icon_system_name": string,    // an SF Symbol name (e.g. pills.fill, drop.fill, syringe.fill, fork.knife, leaf.fill) — NEVER an emoji
          "timing": string,              // short: AM, PM, "With food", "2×", "As directed"
          "benefit": string,             // 1-2 sentences on primary benefit/use
          "mechanism": string,           // 1-2 sentences on how it works
          "best_time_reason": string,    // why/when to take it for best effect
          "interaction_notes": string,   // notable interactions/warnings, or "" if none well-known
          "pros": [string],              // up to 4 short bullets
          "cons": [string],              // up to 4 short bullets
          "citations": [string],         // source names or URLs you used
          "confidence": number           // 0.0–1.0 self-assessed accuracy
        }
        """

        let userMessage = AIService.Message(role: "user", content: "Research: \(q)")

        // OpenRouter exposes web grounding via the ":online" model suffix. Fall back
        // to the plain model if grounding produces nothing usable.
        let baseModel = "meta-llama/llama-4-maverick"
        let model = preferWebGrounding ? baseModel + ":online" : baseModel

        let raw: String
        do {
            raw = try await AIService.shared.complete(
                messages: [userMessage],
                systemPrompt: system,
                model: model,
                temperature: 0.2,
                maxTokens: 900
            )
        } catch {
            // Retry once without web grounding before giving up.
            guard preferWebGrounding else { return nil }
            return await research(query: q, preferWebGrounding: false)
        }

        return decode(raw, fallbackName: q)
    }

    // MARK: - Decoding

    private struct Payload: Decodable {
        let name: String?
        let aliases: [String]?
        let category: String?
        let default_dose: String?
        let icon_system_name: String?
        let timing: String?
        let benefit: String?
        let mechanism: String?
        let best_time_reason: String?
        let interaction_notes: String?
        let pros: [String]?
        let cons: [String]?
        let citations: [String]?
        let confidence: Double?
    }

    /// Extracts the JSON object from a possibly-noisy model response and maps it to
    /// a `ResearchedProduct`. Exposed `internal` so unit tests can exercise parsing
    /// without a network call.
    static func decode(_ raw: String, fallbackName: String) -> ResearchedProduct? {
        guard let jsonString = extractJSONObject(from: raw),
              let data = jsonString.data(using: .utf8),
              let p = try? JSONDecoder().decode(Payload.self, from: data) else {
            return nil
        }

        let name = (p.name?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
            ?? fallbackName
        let category = normalizeCategory(p.category)
        let icon = sanitizeSymbol(p.icon_system_name, category: category)
        let confidence = min(max(p.confidence ?? 0.5, 0.0), 1.0)

        return ResearchedProduct(
            name: name,
            aliases: (p.aliases ?? []).map { $0.lowercased() },
            category: category,
            defaultDose: p.default_dose ?? "",
            iconSystemName: icon,
            timing: (p.timing?.isEmpty == false ? p.timing! : defaultTiming(for: category)),
            benefit: p.benefit ?? "",
            mechanism: p.mechanism ?? "",
            bestTimeReason: p.best_time_reason ?? "",
            interactionNotes: p.interaction_notes ?? "",
            pros: Array((p.pros ?? []).prefix(4)),
            cons: Array((p.cons ?? []).prefix(4)),
            citations: p.citations ?? [],
            confidence: confidence
        )
    }

    /// Pulls the first balanced `{ ... }` block out of arbitrary text (handles
    /// models that wrap JSON in prose or code fences).
    private static func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var idx = start
        while idx < text.endIndex {
            let ch = text[idx]
            if inString {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
            } else {
                switch ch {
                case "\"": inString = true
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 {
                        return String(text[start...idx])
                    }
                default: break
                }
            }
            idx = text.index(after: idx)
        }
        return nil
    }

    private static func normalizeCategory(_ raw: String?) -> String {
        let c = (raw ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        switch c {
        case "medication", "drug", "rx", "otc": return "medication"
        case "vitamin", "mineral": return "vitamin"
        case "peptide": return "peptide"
        case "food", "meal", "snack", "beverage", "drink": return "food"
        default: return "supplement"
        }
    }

    /// Guard against the model returning an emoji or junk in the symbol slot
    /// (design rule: SF Symbols only). Accepts only symbol-name-shaped strings.
    private static func sanitizeSymbol(_ raw: String?, category: String) -> String {
        let s = (raw ?? "").trimmingCharacters(in: .whitespaces)
        let looksLikeSymbol = !s.isEmpty
            && s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
            && s.contains(where: { $0.isLetter })
        if looksLikeSymbol { return s }
        switch category {
        case "medication": return "pills.fill"
        case "peptide": return "syringe.fill"
        case "vitamin": return "drop.fill"
        case "food": return "fork.knife"
        default: return "pills.fill"
        }
    }

    private static func defaultTiming(for category: String) -> String {
        switch category {
        case "peptide": return "PM"
        case "medication": return "As directed"
        default: return "AM"
        }
    }
}
