import Foundation

// MARK: - Sub-App Guardrails (roadmap D3)
//
// Safety + conformance layer that sits on top of `SubAppSpecValidator`. Where the
// validator enforces structural correctness, guardrails enforce *policy*:
//   - size limits so generated sub-apps stay small and on-brand,
//   - reserved-id protection so user/installed specs can't shadow a built-in,
//   - a content safety screen that blocks medical/diagnostic or otherwise risky
//     framing (this is a wellness app, not a medical device),
//   - a derived list of permissions to surface for explicit user review before save.
//
// `SpecSubApp` (origin `.userCreated`/`.installed`) is the only thing these apply to;
// built-ins are trusted Swift.

enum SubAppGuardrails {
    // Size limits — keep generated apps simple, fast to render, and reviewable.
    static let maxEntities = 4
    static let maxFieldsPerEntity = 8
    static let maxScreens = 6
    static let maxSelectionOptions = 12

    /// IDs reserved for built-in sub-apps + the built-in demo specs. User-created /
    /// installed specs may not use these (prevents shadowing core features + data).
    static var reservedIDs: Set<String> {
        var ids = Set(AppModule.allCases.map { $0.rawValue })
        ids.formUnion(["activity", "health", "journal", "stress", "meditation", "symptoms_labs"])
        ids.formUnion(BuiltInSpecs.all.map { $0.id })
        return ids
    }

    /// Phrases that imply medical diagnosis/treatment claims. Blocked in user-facing
    /// spec text so generated sub-apps don't masquerade as medical advice.
    private static let unsafePhrases = [
        "diagnose", "diagnosis", "cure", "treat ", "treatment", "prescribe",
        "prescription", "medical advice", "guaranteed", "fda approved",
    ]

    struct Report {
        var blockers: [SubAppSpecIssue]   // must be fixed before save
        var warnings: [SubAppSpecIssue]
        /// Permissions the user must explicitly approve before the sub-app is saved.
        var permissionsToReview: [SubAppPermission]
        var canSave: Bool { blockers.isEmpty }
    }

    /// Run the full guardrail review for a `.userCreated` / `.installed` spec. This
    /// assumes the spec already passed `SubAppSpecValidator` (structural checks).
    static func review(_ spec: SubAppSpec) -> Report {
        var blockers: [SubAppSpecIssue] = []
        var warnings: [SubAppSpecIssue] = []

        func block(_ path: String, _ msg: String) {
            blockers.append(.init(severity: .error, path: path, message: msg))
        }
        func warn(_ path: String, _ msg: String) {
            warnings.append(.init(severity: .warning, path: path, message: msg))
        }

        // Reserved id.
        if reservedIDs.contains(spec.id) {
            block("id", "'\(spec.id)' is reserved by a built-in sub-app; choose a different id")
        }

        // Size limits.
        if spec.entities.count > maxEntities {
            block("entities", "too many entities (\(spec.entities.count) > \(maxEntities))")
        }
        if spec.screens.count > maxScreens {
            block("screens", "too many screens (\(spec.screens.count) > \(maxScreens))")
        }
        for (i, entity) in spec.entities.enumerated() {
            if entity.fields.count > maxFieldsPerEntity {
                block("entities[\(i)].fields", "too many fields (\(entity.fields.count) > \(maxFieldsPerEntity))")
            }
            for (j, field) in entity.fields.enumerated() where field.type == .selection {
                if field.options.count > maxSelectionOptions {
                    block("entities[\(i)].fields[\(j)].options",
                          "too many options (\(field.options.count) > \(maxSelectionOptions))")
                }
                if field.options.isEmpty {
                    warn("entities[\(i)].fields[\(j)].options", "selection field has no options")
                }
            }
        }

        // Content safety on user-facing text.
        let haystacks: [(String, String)] = [("displayName", spec.displayName), ("summary", spec.summary)]
            + spec.entities.enumerated().map { ("entities[\($0.offset)].label", $0.element.label) }
        for (path, text) in haystacks {
            if let hit = matchedUnsafePhrase(in: text) {
                block(path, "contains disallowed medical/claim language ('\(hit)'); this is a wellness app, not a medical device")
            }
        }

        return Report(
            blockers: blockers,
            warnings: warnings,
            permissionsToReview: spec.permissions.sorted { $0.rawValue < $1.rawValue }
        )
    }

    private static func matchedUnsafePhrase(in text: String) -> String? {
        let lower = text.lowercased()
        return unsafePhrases.first { lower.contains($0) }?.trimmingCharacters(in: .whitespaces)
    }

    /// Human-readable explanation of what a permission lets a sub-app do (for the
    /// review prompt).
    static func explain(_ permission: SubAppPermission) -> String {
        switch permission {
        case .healthRead: return "Read your health & ring metrics"
        case .healthWrite: return "Write health entries on your behalf"
        case .notifications: return "Send you notifications"
        case .network: return "Make network requests"
        case .camera: return "Use the camera"
        case .microphone: return "Use the microphone"
        case .location: return "Access your location"
        }
    }
}
