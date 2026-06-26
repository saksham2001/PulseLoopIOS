import Foundation
import SwiftData

// MARK: - Safe apply pipeline for module improvements (Life OS T5)
//
// The single, guarded path that turns a `ModuleImprovementProposal` into a real
// module update. Used by both the opt-in auto-apply (non-breaking only) and the
// user-confirmed apply. Every apply: re-validates, re-checks guardrails, persists the
// versioned spec, reloads the registry, runs the module's data migration, and records
// the new installed version so the rest of the app sees a clean version bump.

enum ModuleImprovementApplier {
    enum Outcome: Equatable {
        case applied(SemanticVersion)
        case needsConfirmation     // breaking, or auto-apply disabled
        case rejected(String)      // failed validation/guardrails
        case notInstalled
    }

    /// Decide + perform. For non-breaking proposals with auto-apply opted in, applies
    /// immediately; otherwise reports `.needsConfirmation` so the UI/coach can stage a
    /// confirm card. Always re-validates first (defense in depth).
    @MainActor
    @discardableResult
    static func process(
        _ proposal: ModuleImprovementProposal,
        autoApplyNonBreaking: Bool,
        context: ModelContext
    ) -> Outcome {
        guard SubAppRegistry.shared.isInstalled(SubAppID(proposal.moduleId)) else {
            return .notInstalled
        }
        if let reason = validationFailure(proposal.proposedSpec) {
            return .rejected(reason)
        }
        if proposal.isBreaking || !autoApplyNonBreaking {
            return .needsConfirmation
        }
        let applied = commit(proposal, context: context)
        return .applied(applied)
    }

    /// Commit the proposal unconditionally (called after a user confirm, or by
    /// `process` for an auto-eligible non-breaking change). Returns the new version.
    @MainActor
    @discardableResult
    static func commit(_ proposal: ModuleImprovementProposal, context: ModelContext) -> SemanticVersion {
        let spec = proposal.proposedSpec
        let origin = UserSubAppStore.shared.origin(for: spec.id)
        // Persist the new versioned spec (preserving the module's origin), then reload
        // so the running registry reflects the new shape.
        UserSubAppStore.shared.save(spec, origin: origin)
        SubAppRegistry.shared.loadUserSpecs()
        // Migrate forward + stamp the installed version through the unified ledger so
        // `availableUpdate(for:)` stays consistent.
        SubAppRegistry.shared.applyImprovedVersion(SubAppID(spec.id),
                                                   from: proposal.baseVersion,
                                                   to: spec.version,
                                                   context: context)
        ModuleImprovementStore.shared.clear(moduleId: spec.id)
        return spec.version
    }

    /// nil when the spec is safe to install; a short reason otherwise.
    static func validationFailure(_ spec: SubAppSpec) -> String? {
        let errors = SubAppSpecValidator.issues(in: spec).filter { $0.severity == .error }
        if !errors.isEmpty {
            return errors.map { "\($0.path): \($0.message)" }.joined(separator: "; ")
        }
        let report = SubAppGuardrails.review(spec)
        if !report.canSave {
            return report.blockers.map { $0.message }.joined(separator: "; ")
        }
        return nil
    }
}

// MARK: - Daily improvement runner

/// Runs the improvement agent across installed declarative modules on a daily cadence
/// (at most once per local day). Non-breaking proposals auto-apply when the user opted
/// in; everything else is staged for review. Pure scheduling logic + a single entry
/// point so it's easy to test and to call on launch/foreground.
@MainActor
enum ModuleImprovementRunner {
    private static let lastRunKey = "pulseloop.modules.improvements.lastRunDay"

    static func dayKey(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Run if a day has passed since the last run. Returns the proposals produced this
    /// run (staged or applied). No-op (returns []) when already run today.
    @discardableResult
    static func runIfDue(
        context: ModelContext,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> [ModuleImprovementProposal] {
        let today = dayKey(for: now)
        if defaults.string(forKey: lastRunKey) == today { return [] }
        defaults.set(today, forKey: lastRunKey)
        return run(context: context, now: now)
    }

    /// Run unconditionally over all installed declarative modules. Exposed for tests.
    @discardableResult
    static func run(context: ModelContext, now: Date = Date()) -> [ModuleImprovementProposal] {
        let store = ModuleImprovementStore.shared
        let auto = store.autoApplyNonBreaking
        var produced: [ModuleImprovementProposal] = []

        for spec in UserSubAppStore.shared.specs {
            guard SubAppRegistry.shared.isInstalled(SubAppID(spec.id)) else { continue }
            // Don't pile up: skip modules that already have a pending proposal.
            if store.proposal(for: spec.id) != nil { continue }
            guard let proposal = ModuleImprovementAgent.propose(for: spec, now: now) else { continue }

            // Self-healing repairs and opted-in non-breaking enhancements apply
            // automatically; everything else is staged for an explicit decision.
            let canAuto = (proposal.isRepair || auto) && !proposal.isBreaking
            if canAuto, ModuleImprovementApplier.validationFailure(proposal.proposedSpec) == nil {
                ModuleImprovementApplier.commit(proposal, context: context)
            } else {
                store.stage(proposal)
            }
            produced.append(proposal)
        }
        return produced
    }
}
