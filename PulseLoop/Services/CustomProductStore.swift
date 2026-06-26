import Foundation
import SwiftData
import os

// MARK: - Custom Product Store (persisted catalog façade)
//
// The persistence + lookup layer for `CustomProductInfo` — the reusable catalog
// rows the unified search engine discovers outside the bundled knowledge bases
// (AI research pass, Open Food Facts, openFDA). Saving here means the next lookup
// for the same item is instant and it flows back into autocomplete + fuzzy match
// alongside `SupplementKnowledge`.
//
// De-dupe is by normalized name + aliases so re-discovering the same product
// updates the existing row instead of creating duplicates. All conversions go
// through `SupplementInfo` so persisted entries are interchangeable with bundled
// ones in the result/result-card layer.
@MainActor
enum CustomProductStore {

    // MARK: Normalization

    static func normalize(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Conversion

    /// A persisted row as a `SupplementInfo` so it slots into the existing search /
    /// autocomplete / result paths unchanged.
    static func toSupplementInfo(_ p: CustomProductInfo) -> SupplementInfo {
        SupplementInfo(
            name: p.name,
            aliases: p.aliases,
            category: p.category,
            defaultDose: p.defaultDose,
            emoji: p.iconSystemName,
            timing: p.timing,
            benefit: p.benefit,
            mechanism: p.mechanism,
            bestTimeReason: p.bestTimeReason,
            stackNotes: p.stackNotes,
            interactionNotes: p.interactionNotes,
            pros: p.pros,
            cons: p.cons
        )
    }

    // MARK: Lookup

    /// All persisted rows (unsorted). Tolerant of fetch failure.
    static func all(_ context: ModelContext) -> [CustomProductInfo] {
        (try? context.fetch(FetchDescriptor<CustomProductInfo>())) ?? []
    }

    /// Exact-ish match: name equals the query, or an alias contains/contained-by it.
    /// Mirrors `SupplementKnowledge.find` semantics.
    static func find(_ query: String, in context: ModelContext) -> CustomProductInfo? {
        let q = normalize(query)
        guard !q.isEmpty else { return nil }
        return all(context).first { p in
            normalize(p.name) == q ||
            p.aliases.contains(where: { $0 == q || q.contains($0) || $0.contains(q) })
        }
    }

    /// Word-overlap fuzzy match. Mirrors `SupplementKnowledge.fuzzyMatch` semantics.
    static func fuzzyMatch(_ query: String, in context: ModelContext) -> [CustomProductInfo] {
        let q = normalize(query)
        let words = q.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }
        return all(context).filter { p in
            let name = normalize(p.name)
            let nameMatch = words.contains(where: { name.contains($0) })
            let aliasMatch = p.aliases.contains(where: { alias in
                words.contains(where: { alias.contains($0) || $0.contains(alias) })
            })
            return nameMatch || aliasMatch
        }
    }

    // MARK: Persistence

    /// Save (or update) a discovered profile, de-duped by normalized name + aliases.
    /// Returns the persisted row and whether it was newly created. Skips persistence
    /// only if an identical bundled entry already exists is the CALLER's job — this
    /// store is the custom catalog; callers check `SupplementKnowledge`/`PeptideKnowledge`
    /// first per the search-tier order.
    @discardableResult
    static func upsert(
        name: String,
        aliases: [String] = [],
        category: String = "supplement",
        defaultDose: String = "",
        iconSystemName: String = "pills.fill",
        timing: String = "AM",
        benefit: String = "",
        mechanism: String = "",
        bestTimeReason: String = "",
        stackNotes: String = "",
        interactionNotes: String = "",
        pros: [String] = [],
        cons: [String] = [],
        source: String = "AI research",
        isAIGenerated: Bool = false,
        citations: [String] = [],
        in context: ModelContext
    ) -> (product: CustomProductInfo, created: Bool) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAliases = ([trimmedName] + aliases)
            .map(normalize)
            .filter { !$0.isEmpty }
            .reduced()

        if let existing = find(trimmedName, in: context) {
            // Refresh fields, merge aliases — keep the catalog current without dupes.
            existing.aliases = (existing.aliases + normalizedAliases).reduced()
            existing.category = category
            if !defaultDose.isEmpty { existing.defaultDose = defaultDose }
            existing.iconSystemName = iconSystemName
            if !timing.isEmpty { existing.timing = timing }
            if !benefit.isEmpty { existing.benefit = benefit }
            if !mechanism.isEmpty { existing.mechanism = mechanism }
            if !bestTimeReason.isEmpty { existing.bestTimeReason = bestTimeReason }
            if !stackNotes.isEmpty { existing.stackNotes = stackNotes }
            if !interactionNotes.isEmpty { existing.interactionNotes = interactionNotes }
            if !pros.isEmpty { existing.pros = pros }
            if !cons.isEmpty { existing.cons = cons }
            existing.source = source
            existing.isAIGenerated = isAIGenerated
            if !citations.isEmpty { existing.citations = citations }
            context.saveOrLog("tracker.catalog")
            return (existing, false)
        }

        let product = CustomProductInfo(
            name: trimmedName,
            aliases: normalizedAliases,
            category: category,
            defaultDose: defaultDose,
            iconSystemName: iconSystemName,
            timing: timing,
            benefit: benefit,
            mechanism: mechanism,
            bestTimeReason: bestTimeReason,
            stackNotes: stackNotes,
            interactionNotes: interactionNotes,
            pros: pros,
            cons: cons,
            source: source,
            isAIGenerated: isAIGenerated,
            citations: citations
        )
        context.insert(product)
        context.saveOrLog("tracker.catalog")
        return (product, true)
    }

    /// Convenience: persist a `SupplementInfo` produced by an API/AI tier.
    @discardableResult
    static func upsert(
        _ info: SupplementInfo,
        source: String,
        isAIGenerated: Bool,
        citations: [String] = [],
        in context: ModelContext
    ) -> (product: CustomProductInfo, created: Bool) {
        upsert(
            name: info.name,
            aliases: info.aliases,
            category: info.category,
            defaultDose: info.defaultDose,
            iconSystemName: info.emoji,
            timing: info.timing,
            benefit: info.benefit,
            mechanism: info.mechanism,
            bestTimeReason: info.bestTimeReason,
            stackNotes: info.stackNotes,
            interactionNotes: info.interactionNotes,
            pros: info.pros,
            cons: info.cons,
            source: source,
            isAIGenerated: isAIGenerated,
            citations: citations,
            in: context
        )
    }

    // MARK: Maintenance

    /// Merge any persisted rows that share a normalized name (can happen if older
    /// builds saved before de-dupe was tightened). Keeps the most recently created
    /// row, merges aliases into it, and deletes the rest. Returns the number removed.
    @discardableResult
    static func cleanupDuplicates(in context: ModelContext) -> Int {
        let rows = all(context)
        guard rows.count > 1 else { return 0 }
        var groups: [String: [CustomProductInfo]] = [:]
        for r in rows {
            groups[normalize(r.name), default: []].append(r)
        }
        var removed = 0
        for (_, dupes) in groups where dupes.count > 1 {
            let sorted = dupes.sorted { $0.createdAt > $1.createdAt }
            guard let keep = sorted.first else { continue }
            for victim in sorted.dropFirst() {
                keep.aliases = (keep.aliases + victim.aliases).reduced()
                context.delete(victim)
                removed += 1
            }
        }
        if removed > 0 { context.saveOrLog("tracker.catalog") }
        return removed
    }
}

private extension Array where Element == String {
    /// Order-preserving de-dupe.
    func reduced() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0).inserted }
    }
}
