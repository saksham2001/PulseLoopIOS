import Foundation
import SwiftData

/// Runs the once-per-day "knowledge base" pass: reviews the user's recent data
/// and persists durable `DailyLearning` insights the coach reuses. Self-gating —
/// safe to call on every app open. Uses the shared OpenRouter-backed `AIService`
/// (no user API key required), and never fabricates insights (the model returns
/// an empty list when data is too thin).
@MainActor
final class DailyLearningService {
    private let modelContext: ModelContext
    private let ai: AIService

    /// UserDefaults key holding the last `signature` we generated for, so a day
    /// with no new data doesn't trigger a redundant LLM call.
    private static let lastSignatureKey = "dailyLearningLastSignature"

    init(modelContext: ModelContext, ai: AIService = .shared) {
        self.modelContext = modelContext
        self.ai = ai
    }

    // MARK: - Reads

    /// All learnings, newest-and-most-important first, for the Insights screen.
    func allLearnings() -> [DailyLearning] {
        let descriptor = FetchDescriptor<DailyLearning>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Daily run (self-gating)

    /// Generates today's learnings if the gates pass. Returns the number of new
    /// learnings persisted (0 when skipped or nothing new was found).
    @discardableResult
    func runIfNeeded(now: Date = Date()) async -> Int {
        let built = DailyLearningContextBuilder.build(context: modelContext, now: now)
        guard built.hasMeaningfulData else { return 0 }

        // Once per day: skip if we already ran for this scope date and the data
        // signature hasn't changed.
        if alreadyRan(scope: built.scopeKey, signature: built.signature) { return 0 }

        let content = await generate(contextJSON: built.json)
        UserDefaults.standard.set(built.signature, forKey: Self.lastSignatureKey)
        guard let content else { return 0 }

        return persist(content, scope: built.scopeKey)
    }

    // MARK: - Generation

    private func generate(contextJSON: String) async -> DailyLearningContent? {
        let prompt = """
        \(Self.developerMessage(contextJSON: contextJSON))

        Respond ONLY with a JSON object in this exact shape (no markdown, no prose):
        {"learnings": [{"title": "string (≤70 chars)", "detail": "string (≤280 chars)", "category": "one of: \(LearningCategory.allCases.map(\.rawValue).joined(separator: ", "))", "importance": 1-5}]}

        Return {"learnings": []} if the data is too thin to learn anything genuinely new.
        Return at most 4 learnings; quality over quantity.
        """

        do {
            let response = try await ai.complete(
                messages: [AIService.Message(role: "user", content: prompt)],
                systemPrompt: Self.systemPrompt,
                temperature: 0.4,
                maxTokens: 700
            )
            return DailyLearningContent.decode(fromJSON: response)
        } catch {
            return nil
        }
    }

    // MARK: - Persistence

    /// Persists new learnings, skipping any whose title duplicates an existing
    /// one (case-insensitive) so the knowledge base grows without repeating.
    private func persist(_ content: DailyLearningContent, scope: String) -> Int {
        let existingTitles = Set(allLearnings().map { $0.title.lowercased() })
        var added = 0
        for item in content.learnings {
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = item.detail.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !detail.isEmpty else { continue }
            guard !existingTitles.contains(title.lowercased()) else { continue }
            let learning = DailyLearning(
                title: title,
                detail: detail,
                category: item.resolvedCategory,
                importance: item.importance,
                sourceDate: scope
            )
            modelContext.insert(learning)
            added += 1
        }
        if added > 0 { modelContext.saveOrLog("coach.learning") }
        return added
    }

    // MARK: - Gates

    private func alreadyRan(scope: String, signature: String) -> Bool {
        // Already produced a learning today → done for the day.
        let descriptor = FetchDescriptor<DailyLearning>(
            predicate: #Predicate { $0.sourceDate == scope }
        )
        if let count = try? modelContext.fetchCount(descriptor), count > 0 { return true }
        // Or we already attempted this exact data signature (handles the
        // "ran but found nothing new" case so we don't re-call repeatedly).
        return UserDefaults.standard.string(forKey: Self.lastSignatureKey) == signature
    }

    // MARK: - Prompts

    private static let systemPrompt = """
    You are the knowledge engine inside a personal health app. Once a day you review the user's recent data and distill DURABLE, PERSONAL learnings — patterns, correlations, and takeaways that will help coach this specific person over time.

    Rules:
    - Ground every learning strictly in the provided data. Never invent numbers or claims.
    - Prefer cross-metric patterns (e.g. "alcohol nights drop your sleep score ~12 pts") over restating a single day's value.
    - Each learning must be NEW relative to existing_learnings. Refine or skip rather than repeat.
    - If the data is too sparse to learn anything genuinely useful, return an empty learnings array. Do NOT pad.
    - No medical diagnosis. Use cautious, non-alarming language for health interpretations.
    - Titles are short and concrete (≤70 chars). Detail is one or two plain sentences (≤280 chars).
    - importance: 5 = strong, actionable, well-supported pattern; 1 = weak/tentative.
    - Choose the single best-fitting category from the allowed list.
    - Output ONLY valid JSON. No markdown fences, no commentary.
    """

    private static func developerMessage(contextJSON: String) -> String {
        """
        Here is the user's recent data (a rolling window). Extract durable learnings per the rules.

        DATA:
        \(contextJSON)
        """
    }
}
