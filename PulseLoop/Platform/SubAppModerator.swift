import Foundation

// MARK: - Sub-App Moderation + versioned updates (roadmap F3)
//
// A moderation pass that the registry runs before a spec is published or an update
// is installed. It layers on top of `SubAppSpecValidator` (structure) and
// `SubAppGuardrails` (policy) with a deeper, all-text content scan and a single
// verdict the UI can act on. v1 runs locally + deterministically; the backend (E3)
// can replace `moderate(_:)` with a server call returning the same verdict shape.

enum ModerationVerdict: Equatable {
    /// Safe to publish/install.
    case approved
    /// Installable but the user should be warned (non-blocking concerns).
    case flagged([String])
    /// Must not be published/installed.
    case rejected([String])

    var isInstallable: Bool {
        switch self {
        case .approved, .flagged: return true
        case .rejected: return false
        }
    }

    var reasons: [String] {
        switch self {
        case .approved: return []
        case .flagged(let r), .rejected(let r): return r
        }
    }
}

enum SubAppModerator {
    /// Phrases that get a spec outright rejected (harmful / deceptive framing). These
    /// are stricter than the builder guardrails because installed apps run others'
    /// content.
    private static let rejectPhrases = [
        "diagnose", "diagnosis", "cure", "prescription", "prescribe",
        "self-harm", "suicide method", "illegal drug", "how to make a weapon",
        "fda approved", "guaranteed results",
    ]

    /// Phrases that flag (warn) but don't block — borderline wellness claims.
    private static let flagPhrases = [
        "lose weight fast", "miracle", "detox", "boost immunity", "anti-aging",
    ]

    /// Full content moderation pass over every user-facing string in the spec.
    static func moderate(_ spec: SubAppSpec) -> ModerationVerdict {
        // Structural + policy gates first — a spec that fails these can't be installed.
        if (try? SubAppSpecValidator.validate(spec)) == nil {
            return .rejected(["Spec failed validation."])
        }
        let guardrail = SubAppGuardrails.review(spec)
        if !guardrail.canSave {
            return .rejected(guardrail.blockers.map { $0.message })
        }

        var rejects: [String] = []
        var flags: [String] = []
        for text in userFacingStrings(spec) {
            let lower = text.lowercased()
            for phrase in rejectPhrases where lower.contains(phrase) {
                rejects.append("Disallowed content: \"\(phrase)\".")
            }
            for phrase in flagPhrases where lower.contains(phrase) {
                flags.append("Borderline wellness claim: \"\(phrase)\".")
            }
        }

        if !rejects.isEmpty { return .rejected(Array(Set(rejects)).sorted()) }
        if !flags.isEmpty { return .flagged(Array(Set(flags)).sorted()) }
        return .approved
    }

    /// Every string a person would read in the spec — names, labels, options, titles.
    private static func userFacingStrings(_ spec: SubAppSpec) -> [String] {
        var out = [spec.displayName, spec.summary, spec.author]
        for entity in spec.entities {
            out.append(entity.label)
            for field in entity.fields {
                out.append(field.label)
                out.append(contentsOf: field.options)
            }
        }
        out.append(contentsOf: spec.screens.map { $0.title })
        return out.filter { !$0.isEmpty }
    }
}
