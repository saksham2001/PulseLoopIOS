import Foundation
import Combine

// MARK: - Module self-improvement (Life OS T5)
//
// A per-module improvement agent that, on a periodic cadence, PROPOSES a better
// version of an installed declarative module as a `SubAppSpec` diff — it never edits
// the live module in place. Proposals go through the same safety pipeline as any
// update: validate → guardrails → version bump → confirm gate → migrate. Only
// non-breaking (additive, data-preserving) changes may auto-apply, and only when the
// user has opted in. Breaking changes always require an explicit confirm.
//
// It also SELF-HEALS: if an installed spec no longer validates (e.g. a schema or
// guardrail tightened), the agent proposes a repaired version.
//
// The authoring heuristic here is deterministic and offline (so it's fully testable
// and never silently breaks a module). An LLM author can plug into the same
// `propose(for:)` seam later — the safety pipeline downstream is unchanged.

/// A staged improvement awaiting the user's decision (or eligible for opt-in
/// auto-apply when non-breaking).
struct ModuleImprovementProposal: Codable, Hashable, Identifiable {
    let moduleId: String
    let baseVersion: SemanticVersion
    let proposedSpec: SubAppSpec
    let rationale: String
    /// Cached classification so the UI/store doesn't recompute the diff.
    let isBreaking: Bool
    let createdAt: Date
    /// True when this proposal repairs an invalid installed spec (self-healing).
    let isRepair: Bool

    var id: String { moduleId }
    var proposedVersion: SemanticVersion { proposedSpec.version }
}

// MARK: - Agent

enum ModuleImprovementAgent {
    /// Propose an improved spec for an installed module, or nil when there's nothing
    /// worthwhile to change. Pure given its inputs.
    ///
    /// Strategy (conservative, additive-first):
    ///   1. Self-heal: if the spec is invalid, return a repaired version.
    ///   2. Otherwise suggest safe additive improvements that make the module more
    ///      useful: a "Notes" field on entities that lack a free-text field, and an
    ///      overview dashboard screen when the module has none.
    static func propose(for spec: SubAppSpec, now: Date = Date()) -> ModuleImprovementProposal? {
        if let repair = repairProposal(for: spec, now: now) { return repair }
        return enhancementProposal(for: spec, now: now)
    }

    // MARK: Self-healing

    private static func repairProposal(for spec: SubAppSpec, now: Date) -> ModuleImprovementProposal? {
        let errors = SubAppSpecValidator.issues(in: spec).filter { $0.severity == .error }
        let guardrailOK = SubAppGuardrails.review(spec).canSave
        guard !errors.isEmpty || !guardrailOK else { return nil }

        var fixed = spec
        // Heuristic repairs that preserve user intent:
        //  - an entity with no fields gets a minimal text field
        //  - an entity referenced by a screen but missing gets created
        fixed.entities = fixed.entities.map { entity in
            guard entity.fields.isEmpty else { return entity }
            var e = entity
            e.fields = [FieldSpec(name: "note", label: "Note", type: .text)]
            return e
        }
        let knownEntities = Set(fixed.entities.map { $0.name })
        fixed.screens = fixed.screens.map { screen in
            guard let entity = screen.entity, !entity.isEmpty, !knownEntities.contains(entity) else { return screen }
            var s = screen
            s.entity = nil  // detach a dangling reference rather than invent data
            return s
        }
        fixed.version = bump(spec.version, breaking: false)

        // Only offer the repair if it actually validates now.
        guard SubAppSpecValidator.issues(in: fixed).filter({ $0.severity == .error }).isEmpty,
              SubAppGuardrails.review(fixed).canSave else { return nil }

        return ModuleImprovementProposal(
            moduleId: spec.id,
            baseVersion: spec.version,
            proposedSpec: fixed,
            rationale: "Repairs a validation issue so \(spec.displayName) keeps working.",
            isBreaking: SubAppSpecDiff.between(spec, fixed).isBreaking,
            createdAt: now,
            isRepair: true
        )
    }

    // MARK: Additive enhancement

    private static func enhancementProposal(for spec: SubAppSpec, now: Date) -> ModuleImprovementProposal? {
        var improved = spec
        var changed = false
        var reasons: [String] = []

        // 1. Add an optional free-text "Notes" field to entities that have none, so
        //    users can capture context (additive ⇒ non-breaking).
        improved.entities = improved.entities.map { entity in
            let hasFreeText = entity.fields.contains { $0.type == .text && !$0.required }
            let hasNotes = entity.fields.contains { $0.name == "notes" }
            guard !hasFreeText && !hasNotes else { return entity }
            var e = entity
            e.fields.append(FieldSpec(name: "notes", label: "Notes", type: .text))
            changed = true
            reasons.append("a Notes field on \(entity.label)")
            return e
        }

        // 2. Add an overview dashboard if the module has none (additive ⇒ non-breaking).
        if !improved.screens.contains(where: { $0.kind == .dashboard }) {
            improved.screens.append(ScreenSpec(id: "overview", title: "Overview", kind: .dashboard, entity: nil))
            changed = true
            reasons.append("an Overview dashboard")
        }

        guard changed else { return nil }
        let diff = SubAppSpecDiff.between(spec, improved)
        guard !diff.isEmpty else { return nil }
        improved.version = bump(spec.version, breaking: diff.isBreaking)

        // Never propose something that wouldn't pass the safety gates anyway.
        guard SubAppSpecValidator.issues(in: improved).filter({ $0.severity == .error }).isEmpty,
              SubAppGuardrails.review(improved).canSave else { return nil }

        return ModuleImprovementProposal(
            moduleId: spec.id,
            baseVersion: spec.version,
            proposedSpec: improved,
            rationale: "Suggests \(reasons.joined(separator: " and ")) to make \(spec.displayName) more useful.",
            isBreaking: diff.isBreaking,
            createdAt: now,
            isRepair: false
        )
    }

    /// A monotonic version bump: minor for non-breaking, major for breaking.
    static func bump(_ version: SemanticVersion, breaking: Bool) -> SemanticVersion {
        breaking
            ? SemanticVersion(major: version.major + 1, minor: 0, patch: 0)
            : SemanticVersion(major: version.major, minor: version.minor + 1, patch: 0)
    }
}

// MARK: - Store

/// Persists at most one pending improvement proposal per module (UserDefaults), plus
/// the user's opt-in for auto-applying non-breaking improvements.
@MainActor
final class ModuleImprovementStore: ObservableObject {
    static let shared = ModuleImprovementStore()

    private static let proposalsKey = "pulseloop.modules.improvements.v1"
    private static let autoApplyKey = "pulseloop.modules.improvements.autoApply"
    private let defaults: UserDefaults

    @Published private(set) var proposals: [String: ModuleImprovementProposal] = [:]

    /// When true, non-breaking proposals are applied automatically (still validated +
    /// versioned + migrated). Breaking changes always need confirmation. Default OFF.
    var autoApplyNonBreaking: Bool {
        get { defaults.bool(forKey: Self.autoApplyKey) }
        set { defaults.set(newValue, forKey: Self.autoApplyKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.proposalsKey),
           let decoded = try? JSONDecoder().decode([String: ModuleImprovementProposal].self, from: data) {
            proposals = decoded
        }
    }

    func proposal(for moduleId: String) -> ModuleImprovementProposal? { proposals[moduleId] }
    var pending: [ModuleImprovementProposal] {
        proposals.values.sorted { $0.createdAt > $1.createdAt }
    }

    func stage(_ proposal: ModuleImprovementProposal) {
        proposals[proposal.moduleId] = proposal
        persist()
    }

    func clear(moduleId: String) {
        proposals.removeValue(forKey: moduleId)
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(proposals) {
            defaults.set(data, forKey: Self.proposalsKey)
        }
    }
}
