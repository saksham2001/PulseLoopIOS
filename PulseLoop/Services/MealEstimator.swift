import Foundation

// MARK: - Meal Estimator (AI-first NL meal capture — Tracker C2)
//
// Turns a free-text meal description ("two eggs, toast and a coffee") into a
// structured nutrition estimate. Tries the AI (structured JSON) first for arbitrary
// foods, then falls back to the deterministic keyword `SupplementKnowledge.estimateMeal`
// so the feature works offline / without an API key.

struct MealEstimate {
    let name: String
    let emoji: String          // SF Symbol
    let calories: Int
    let proteinG: Double?
    let carbsG: Double?
    let fatG: Double?
    let note: String
    let isAIGenerated: Bool

    var macroSummary: String {
        var parts = ["~\(calories) kcal"]
        if let p = proteinG { parts.append("\(Int(p))g protein") }
        if let c = carbsG { parts.append("\(Int(c))g carbs") }
        if let f = fatG { parts.append("\(Int(f))g fat") }
        return parts.joined(separator: " · ")
    }
}

@MainActor
enum MealEstimator {

    /// Deterministic, instant estimate from the bundled keyword table. Always available.
    static func quickEstimate(_ description: String) -> MealEstimate? {
        guard let i = SupplementKnowledge.estimateMeal(description) else { return nil }
        return MealEstimate(
            name: i.name,
            emoji: i.emoji,
            calories: i.estimatedCalories,
            proteinG: i.estimatedProtein,
            carbsG: i.estimatedCarbs,
            fatG: i.estimatedFat,
            note: i.supplementNote ?? "",
            isAIGenerated: false
        )
    }

    /// AI estimate for arbitrary meals. Falls back to `quickEstimate` when no AI key
    /// is configured, the network fails, or output is unusable — never throws.
    static func estimate(_ description: String) async -> MealEstimate? {
        let d = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !d.isEmpty else { return nil }

        guard AIService.shared.hasAPIKey else { return quickEstimate(d) }

        let system = """
        You estimate nutrition for a described meal. Respond with ONLY a JSON object:
        {
          "name": string,            // short title for the meal
          "icon_system_name": string,// an SF Symbol (fork.knife, cup.and.saucer.fill, leaf.fill, mug.fill, drop.fill) — NEVER an emoji
          "calories": number,        // total kcal estimate
          "protein_g": number,
          "carbs_g": number,
          "fat_g": number,
          "note": string             // one short helpful note (or "")
        }
        Estimate reasonable totals for the whole described meal. No prose, JSON only.
        """

        do {
            let raw = try await AIService.shared.complete(
                messages: [AIService.Message(role: "user", content: "Meal: \(d)")],
                systemPrompt: system,
                temperature: 0.2,
                maxTokens: 300
            )
            if let est = decode(raw, fallbackName: d) { return est }
        } catch {
            // fall through to deterministic
        }
        return quickEstimate(d)
    }

    // MARK: Decoding (test-visible)

    private struct Payload: Decodable {
        let name: String?
        let icon_system_name: String?
        let calories: Double?
        let protein_g: Double?
        let carbs_g: Double?
        let fat_g: Double?
        let note: String?
    }

    static func decode(_ raw: String, fallbackName: String) -> MealEstimate? {
        guard let json = extractJSONObject(from: raw),
              let data = json.data(using: .utf8),
              let p = try? JSONDecoder().decode(Payload.self, from: data),
              let cal = p.calories else {
            return nil
        }
        let icon = sanitizeSymbol(p.icon_system_name)
        return MealEstimate(
            name: (p.name?.isEmpty == false ? p.name! : fallbackName),
            emoji: icon,
            calories: Int(cal.rounded()),
            proteinG: p.protein_g,
            carbsG: p.carbs_g,
            fatG: p.fat_g,
            note: p.note ?? "",
            isAIGenerated: true
        )
    }

    private static func sanitizeSymbol(_ raw: String?) -> String {
        let s = (raw ?? "").trimmingCharacters(in: .whitespaces)
        let ok = !s.isEmpty
            && s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
            && s.contains(where: { $0.isLetter })
        return ok ? s : "fork.knife"
    }

    private static func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0, inString = false, escaped = false
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
                    if depth == 0 { return String(text[start...idx]) }
                default: break
                }
            }
            idx = text.index(after: idx)
        }
        return nil
    }
}
