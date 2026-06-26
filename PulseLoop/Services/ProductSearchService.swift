import Foundation
import SwiftData

enum ProductSource: String {
    case localKnowledgeBase = "PulseLoop AI"
    case openFoodFacts = "Open Food Facts"
    case openFDA = "FDA Database"
    case custom = "Custom Entry"
    case aiResearch = "AI Research"
}

struct ProductSearchResult {
    let info: SupplementInfo
    let source: ProductSource
    let confidence: Double
    /// Source names/URLs backing an AI-researched/web-grounded result.
    var citations: [String] = []
    /// True when synthesized by the AI research pass — drives the UI disclaimer
    /// and whether the result should be persisted as a `CustomProductInfo`.
    var isAIGenerated: Bool = false
}

enum ProductSearchService {

    /// Unified search: tries local KB first, then queries all internet sources in parallel.
    ///
    /// Pass `customStore` results (already fetched on the main actor from
    /// `CustomProductStore`) so previously-discovered/persisted items resolve
    /// instantly without re-querying APIs. The `customMatches` are checked right
    /// after the bundled knowledge base and before any network call.
    static func search(query: String, customMatches: [SupplementInfo] = []) async -> [ProductSearchResult] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }

        var results: [ProductSearchResult] = []

        // 1. Local knowledge base (instant)
        if let exact = SupplementKnowledge.find(q) {
            results.append(ProductSearchResult(info: exact, source: .localKnowledgeBase, confidence: 1.0))
        }
        let fuzzy = SupplementKnowledge.fuzzyMatch(q)
        for match in fuzzy where results.first(where: { $0.info.name == match.name }) == nil {
            results.append(ProductSearchResult(info: match, source: .localKnowledgeBase, confidence: 0.8))
        }

        // 1b. Previously-persisted custom catalog (instant; from CustomProductStore)
        for match in customMatches where results.first(where: { $0.info.name == match.name }) == nil {
            results.append(ProductSearchResult(info: match, source: .custom, confidence: 0.85))
        }

        if !results.isEmpty { return results }

        // 2. Query external APIs in parallel
        async let foodResults = OpenFoodFactsService.search(query: q)
        async let fdaResults = OpenFDAService.searchLabels(query: q)

        let foods = await foodResults
        let drugs = await fdaResults

        // Add FDA results (medications)
        for drug in drugs.prefix(3) {
            let info = OpenFDAService.toSupplementInfo(drug)
            results.append(ProductSearchResult(info: info, source: .openFDA, confidence: 0.7))
        }

        // Add Open Food Facts results (supplements/food)
        for product in foods.prefix(3) {
            let info = OpenFoodFactsService.toSupplementInfo(product)
            results.append(ProductSearchResult(info: info, source: .openFoodFacts, confidence: 0.6))
        }

        if !results.isEmpty { return results }

        // 3. AI research pass (the Perplexity tier) — synthesize a structured,
        //    cited profile when local + APIs found nothing. Degrades to the
        //    deterministic inference if no AI key / network is available.
        if let researched = await ProductResearchService.research(query: q) {
            results.append(ProductSearchResult(
                info: researched.asSupplementInfo,
                source: .aiResearch,
                confidence: max(researched.confidence, 0.35),
                citations: researched.citations,
                isAIGenerated: true
            ))
            return results
        }

        // 4. Last resort: deterministic label/name inference.
        let inferred = AIProductInference.infer(from: [q])
        results.append(ProductSearchResult(info: inferred, source: .custom, confidence: 0.3, isAIGenerated: true))

        return results
    }

    // MARK: - Search with persistence (B2)

    /// What a persisting search did with a discovered item, surfaced so the UI can
    /// show "Saved to your catalog".
    struct PersistedSearch {
        let results: [ProductSearchResult]
        /// Names newly saved to the custom catalog this run.
        let persistedNames: [String]
    }

    /// Runs the unified search on the main actor, seeding it with previously-saved
    /// custom catalog entries, and PERSISTS any AI-researched / API-sourced result
    /// that isn't already known locally — so the next search resolves instantly and
    /// the item flows back into autocomplete. De-dupe is handled by `CustomProductStore`.
    @MainActor
    static func searchAndPersist(query: String, in context: ModelContext) async -> PersistedSearch {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return PersistedSearch(results: [], persistedNames: []) }

        // Seed with persisted custom matches so known items short-circuit the network.
        let customMatches = (CustomProductStore.fuzzyMatch(q, in: context)
            + [CustomProductStore.find(q, in: context)].compactMap { $0 })
            .map(CustomProductStore.toSupplementInfo)

        let results = await search(query: q, customMatches: customMatches)

        // Persist discoveries: AI-researched items, or API results (FDA / Open Food
        // Facts) that aren't already in a bundled catalog. Skip bundled-KB + already
        // custom-sourced results (those are known). Only persist confident enough rows.
        var persisted: [String] = []
        for result in results {
            let shouldPersist: Bool
            switch result.source {
            case .aiResearch:
                shouldPersist = true
            case .openFDA, .openFoodFacts:
                shouldPersist = SupplementKnowledge.find(result.info.name) == nil
            case .localKnowledgeBase, .custom:
                shouldPersist = false
            }
            guard shouldPersist, result.confidence >= 0.3 else { continue }

            let (_, created) = CustomProductStore.upsert(
                result.info,
                source: result.source.rawValue,
                isAIGenerated: result.isAIGenerated,
                citations: result.citations,
                in: context
            )
            if created { persisted.append(result.info.name) }
        }

        return PersistedSearch(results: results, persistedNames: persisted)
    }

    /// Search specifically from OCR-detected text (prioritizes longer matches)
    static func searchFromOCR(texts: [String]) async -> ProductSearchResult? {
        let combined = texts.joined(separator: " ").lowercased()

        // Try local knowledge base first
        for info in SupplementKnowledge.database {
            if combined.contains(info.name.lowercased()) {
                return ProductSearchResult(info: info, source: .localKnowledgeBase, confidence: 1.0)
            }
            for alias in info.aliases {
                if combined.contains(alias) {
                    return ProductSearchResult(info: info, source: .localKnowledgeBase, confidence: 0.9)
                }
            }
        }

        let fuzzy = SupplementKnowledge.fuzzyMatch(combined)
        if let best = fuzzy.first {
            return ProductSearchResult(info: best, source: .localKnowledgeBase, confidence: 0.75)
        }

        // Query external APIs with the most promising text segments
        let searchQuery = texts.prefix(5).joined(separator: " ")
        let allResults = await search(query: searchQuery)
        if let first = allResults.first {
            return first
        }

        // If nothing found anywhere, use AI inference to populate data
        let inferred = AIProductInference.infer(from: texts)
        return ProductSearchResult(info: inferred, source: .custom, confidence: 0.4)
    }
}

// MARK: - AI Product Inference

enum AIProductInference {

    static func infer(from texts: [String]) -> SupplementInfo {
        let combined = texts.joined(separator: " ")
        let lower = combined.lowercased()

        let name = extractProductName(from: texts)
        let category = inferCategory(from: lower)
        let dose = extractDose(from: lower)
        let emoji = emojiForCategory(category)
        let timing = inferTiming(from: lower, category: category)
        let benefit = inferBenefit(from: lower, category: category)
        let mechanism = inferMechanism(from: lower, category: category)
        let bestTime = inferBestTime(from: lower, category: category, timing: timing)
        let interactions = inferInteractions(from: lower, category: category)

        return SupplementInfo(
            name: name,
            aliases: [name.lowercased()],
            category: category,
            defaultDose: dose,
            emoji: emoji,
            timing: timing,
            benefit: benefit,
            mechanism: mechanism,
            bestTimeReason: bestTime,
            stackNotes: "AI-inferred entry  -  verify with manufacturer or healthcare provider",
            interactionNotes: interactions,
            pros: [],
            cons: []
        )
    }

    private static func extractProductName(from texts: [String]) -> String {
        // Try to find the most likely product name (largest text, proper nouns, brand-like words)
        let candidates = texts.filter { text in
            let words = text.split(separator: " ")
            return words.count <= 5 && words.count >= 1 && text.count >= 3 && text.count <= 60
        }

        // Prefer lines that start with uppercase and don't look like dosage/directions
        let skipPatterns = ["take", "directions", "serving", "amount", "daily", "supplement facts", "other ingredients", "warning", "store", "keep"]
        let filtered = candidates.filter { line in
            let l = line.lowercased()
            return !skipPatterns.contains(where: { l.hasPrefix($0) })
        }

        if let best = filtered.first(where: { $0.first?.isUppercase == true && $0.count >= 4 }) {
            return best
        }
        return filtered.first ?? texts.first ?? "Unknown Product"
    }

    private static func inferCategory(from text: String) -> String {
        // Medication indicators
        let medSuffixes = ["pril", "olol", "statin", "sartan", "pine", "zole", "mycin", "cillin", "mab", "nib", "tide"]
        let medKeywords = ["tablet", "capsule", "prescription", "rx", "drug facts", "active ingredient", "inactive ingredient", "ndc"]
        if medSuffixes.contains(where: { text.contains($0) }) || medKeywords.contains(where: { text.contains($0) }) {
            return "medication"
        }

        // Peptide indicators
        let peptideKeywords = ["peptide", "subcutaneous", "injection", "reconstitute", "lyophilized", "mcg", "bac water", "bacteriostatic"]
        if peptideKeywords.contains(where: { text.contains($0) }) {
            return "peptide"
        }

        // Vitamin indicators
        let vitaminKeywords = ["vitamin", "vit ", "multivitamin", "b-complex", "b12", "b6", "folate", "biotin"]
        if vitaminKeywords.contains(where: { text.contains($0) }) {
            return "vitamin"
        }

        // Food indicators
        let foodKeywords = ["nutrition facts", "calories", "total fat", "cholesterol", "protein", "serving size", "servings per"]
        if foodKeywords.contains(where: { text.contains($0) }) {
            return "food"
        }

        // Default to supplement for anything with "supplement facts"
        if text.contains("supplement") || text.contains("herbal") || text.contains("extract") {
            return "supplement"
        }

        return "supplement"
    }

    private static func extractDose(from text: String) -> String {
        let pattern = #"(\d+[\.,]?\d*)\s*(mg|mcg|g|iu|ml|mcl|units|billion cfu|capsule|tablet|softgel|drop)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else {
            return "See label for dosage"
        }
        return String(text[range])
    }

    private static func emojiForCategory(_ category: String) -> String {
        switch category {
        case "medication": return "pills.fill"
        case "peptide": return "syringe.fill"
        case "vitamin": return "drop.fill"
        case "food": return "fork.knife"
        default: return "pills.fill"
        }
    }

    private static func inferTiming(from text: String, category: String) -> String {
        if text.contains("before bed") || text.contains("bedtime") || text.contains("evening") || text.contains("pm") {
            return "PM"
        }
        if text.contains("morning") || text.contains("breakfast") || text.contains("am") {
            return "AM"
        }
        if text.contains("twice") || text.contains("2x") || text.contains("bid") {
            return "2×"
        }
        if text.contains("with food") || text.contains("with meal") {
            return "With food"
        }
        switch category {
        case "peptide": return "PM"
        case "medication": return "As directed"
        default: return "AM"
        }
    }

    private static func inferBenefit(from text: String, category: String) -> String {
        // Try to extract purpose or benefit from label text
        let benefitKeywords: [(keyword: String, benefit: String)] = [
            ("immune", "Supports immune system function"),
            ("energy", "Supports energy production and vitality"),
            ("sleep", "Promotes healthy sleep and relaxation"),
            ("joint", "Supports joint health and mobility"),
            ("heart", "Supports cardiovascular health"),
            ("brain", "Supports cognitive function and brain health"),
            ("muscle", "Supports muscle growth and recovery"),
            ("bone", "Supports bone density and strength"),
            ("skin", "Supports skin health and appearance"),
            ("digest", "Supports healthy digestion"),
            ("stress", "Helps manage stress response"),
            ("inflammation", "Supports healthy inflammatory response"),
            ("antioxidant", "Provides antioxidant protection"),
            ("testosterone", "Supports healthy testosterone levels"),
            ("metabolism", "Supports metabolic function"),
            ("liver", "Supports liver health and detoxification"),
            ("gut", "Supports gut health and microbiome balance"),
            ("recovery", "Supports post-exercise recovery"),
            ("focus", "Supports mental focus and clarity"),
            ("mood", "Supports positive mood balance"),
        ]

        let matched = benefitKeywords.filter { text.contains($0.keyword) }
        if !matched.isEmpty {
            return matched.map(\.benefit).prefix(2).joined(separator: ". ")
        }

        switch category {
        case "medication": return "Prescription or OTC medication  -  consult prescriber for indications"
        case "peptide": return "Research peptide  -  consult provider for specific applications"
        case "food": return "Nutritional product  -  check label for full nutritional profile"
        default: return "Dietary supplement  -  check label for intended use"
        }
    }

    private static func inferMechanism(from text: String, category: String) -> String {
        // Extract active ingredients if visible
        var ingredients: [String] = []

        let ingredientPatterns = ["contains:", "ingredients:", "active ingredient", "proprietary blend"]
        for pattern in ingredientPatterns {
            if let range = text.range(of: pattern, options: .caseInsensitive) {
                let after = String(text[range.upperBound...].prefix(150))
                let parts = after.components(separatedBy: CharacterSet(charactersIn: ",.;"))
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && $0.count > 2 }
                ingredients.append(contentsOf: parts.prefix(5))
                break
            }
        }

        if !ingredients.isEmpty {
            return "Contains: " + ingredients.joined(separator: ", ")
        }

        switch category {
        case "medication": return "Pharmaceutical compound  -  see prescribing information for mechanism of action"
        case "peptide": return "Bioactive peptide sequence  -  acts on specific receptor pathways"
        case "vitamin": return "Essential micronutrient required for enzymatic and metabolic processes"
        default: return "Bioactive compound  -  see manufacturer documentation for details"
        }
    }

    private static func inferBestTime(from text: String, category: String, timing: String) -> String {
        if text.contains("empty stomach") {
            return "Take on an empty stomach for best absorption"
        }
        if text.contains("with food") || text.contains("with meal") {
            return "Take with food to improve absorption and reduce GI discomfort"
        }
        if text.contains("fat") && (category == "vitamin" || category == "supplement") {
            return "Take with a fat-containing meal for better bioavailability"
        }

        switch category {
        case "medication": return "Follow prescriber instructions. \(timing) dosing as directed"
        case "peptide": return "Typically administered on empty stomach. Follow protocol instructions"
        case "vitamin": return "Generally best absorbed with a meal containing healthy fats"
        default: return "Follow label directions for optimal timing"
        }
    }

    private static func inferInteractions(from text: String, category: String) -> String {
        var warnings: [String] = []

        if text.contains("warning") || text.contains("caution") {
            if text.contains("pregnant") || text.contains("nursing") {
                warnings.append("Consult doctor if pregnant or nursing")
            }
            if text.contains("blood thin") || text.contains("anticoagulant") {
                warnings.append("May interact with blood thinners")
            }
            if text.contains("medication") && text.contains("consult") {
                warnings.append("Consult doctor if taking other medications")
            }
        }

        if !warnings.isEmpty {
            return warnings.joined(separator: ". ")
        }

        switch category {
        case "medication": return "Check with pharmacist for drug interactions before combining with other medications"
        case "peptide": return "Research compound  -  discuss with prescribing provider before combining with other substances"
        default: return "Generally well-tolerated. Consult healthcare provider if taking prescription medications"
        }
    }
}
