import Foundation

// MARK: - SubAppSpec — declarative sub-app definition (roadmap C1)
//
// A `SubAppSpec` is the serializable description of a sub-app that the AI Sub-App
// Builder produces and the spec runtime (C2/C3) interprets at runtime to conform a
// `SubApp` on the user's behalf. Built-in sub-apps stay hand-written Swift; this
// schema is for `.userCreated` and `.installed` sub-apps.
//
// Design goals:
//   - Strict, versioned, and Codable so specs can be exported/imported/signed (F1).
//   - Reference only design-system widgets — no free-form layout — so generated UI
//     stays on-brand and safe (see .cursor/rules/design-system.mdc).
//   - Permission-explicit: anything the sub-app can touch is declared up front.
//
// This file defines the schema + a strict validator. It does not yet render or
// persist anything (that arrives in C2/C3).

/// The schema version this build understands. Specs carrying a different major
/// version are rejected by the validator. Bump the major when making a breaking
/// change to the shape; bump the minor for backward-compatible additions.
enum SubAppSpecSchema {
    static let current = SemanticVersion(major: 1, minor: 0, patch: 0)
}

/// A minimal semantic-version value type used for spec + schema versioning.
struct SemanticVersion: Codable, Hashable, Comparable, CustomStringConvertible {
    var major: Int
    var minor: Int
    var patch: Int

    init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Parses "MAJOR.MINOR.PATCH". Returns nil for malformed input.
    init?(_ string: String) {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2]),
              major >= 0, minor >= 0, patch >= 0
        else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    /// Tolerant parse: returns `1.0.0` for nil/malformed input instead of failing.
    /// Used to normalize the free-form `SubApp.version` string onto a comparable
    /// value so built-in and spec modules share one versioning model.
    static func parseOrDefault(_ string: String?) -> SemanticVersion {
        guard let string, let parsed = SemanticVersion(string) else {
            return SemanticVersion(major: 1, minor: 0, patch: 0)
        }
        return parsed
    }

    // Encoded as a string so specs read naturally and survive round-trips.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = SemanticVersion(raw) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Invalid semantic version '\(raw)'; expected MAJOR.MINOR.PATCH"
            ))
        }
        self = parsed
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

// MARK: - Spec

/// Top-level declarative description of a sub-app.
struct SubAppSpec: Codable, Hashable {
    /// Schema version this spec was authored against.
    var schemaVersion: SemanticVersion
    /// Stable identifier (becomes the `SubAppID`). Slug-like, see validator rules.
    var id: String
    /// Human-facing name.
    var displayName: String
    /// SF Symbol name (never emoji).
    var icon: String
    /// One-line description.
    var summary: String
    /// Author/owner string.
    var author: String
    /// Sub-app definition version (independent of schema version).
    var version: SemanticVersion
    /// Capabilities this sub-app requests.
    var permissions: [SubAppPermission]
    /// Data model the sub-app stores (dynamic entities, persisted in C3).
    var entities: [EntitySpec]
    /// Screens the sub-app exposes. The first screen is the entry point.
    var screens: [ScreenSpec]

    init(
        schemaVersion: SemanticVersion = SubAppSpecSchema.current,
        id: String,
        displayName: String,
        icon: String,
        summary: String,
        author: String = "User",
        version: SemanticVersion = SemanticVersion(major: 1, minor: 0, patch: 0),
        permissions: [SubAppPermission] = [],
        entities: [EntitySpec] = [],
        screens: [ScreenSpec] = []
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.displayName = displayName
        self.icon = icon
        self.summary = summary
        self.author = author
        self.version = version
        self.permissions = permissions
        self.entities = entities
        self.screens = screens
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, displayName, icon, summary, author, version, permissions, entities, screens
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decodeIfPresent(SemanticVersion.self, forKey: .schemaVersion) ?? SubAppSpecSchema.current
        id = try c.decode(String.self, forKey: .id)
        displayName = try c.decode(String.self, forKey: .displayName)
        icon = try c.decode(String.self, forKey: .icon)
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? "User"
        version = try c.decodeIfPresent(SemanticVersion.self, forKey: .version) ?? SemanticVersion(major: 1, minor: 0, patch: 0)
        permissions = try c.decodeIfPresent([SubAppPermission].self, forKey: .permissions) ?? []
        entities = try c.decodeIfPresent([EntitySpec].self, forKey: .entities) ?? []
        screens = try c.decodeIfPresent([ScreenSpec].self, forKey: .screens) ?? []
    }
}

/// A dynamic data entity (a "table") the sub-app persists.
struct EntitySpec: Codable, Hashable {
    /// Entity name, slug-like (e.g. "habit", "weigh_in").
    var name: String
    /// Human-facing label (e.g. "Habit").
    var label: String
    var fields: [FieldSpec]
}

/// A single field on an entity.
struct FieldSpec: Codable, Hashable {
    var name: String
    var label: String
    var type: FieldType
    var required: Bool
    /// Allowed values for `.selection` fields; ignored for other types.
    var options: [String]

    init(name: String, label: String, type: FieldType, required: Bool = false, options: [String] = []) {
        self.name = name
        self.label = label
        self.type = type
        self.required = required
        self.options = options
    }

    private enum CodingKeys: String, CodingKey { case name, label, type, required, options }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        label = try c.decode(String.self, forKey: .label)
        type = try c.decode(FieldType.self, forKey: .type)
        required = try c.decodeIfPresent(Bool.self, forKey: .required) ?? false
        options = try c.decodeIfPresent([String].self, forKey: .options) ?? []
    }
}

/// The supported field value types. Constrained on purpose so persistence + UI can
/// be generated safely.
enum FieldType: String, Codable, Hashable, CaseIterable {
    case text
    case number
    case integer
    case boolean
    case date
    case rating          // 1...5 integer, rendered as stars
    case selection       // one-of from `options`
}

/// A screen the runtime renders using only design-system widgets.
struct ScreenSpec: Codable, Hashable {
    var id: String
    var title: String
    var kind: ScreenKind
    /// Entity this screen reads/writes, when applicable (list/form/detail).
    var entity: String?
}

/// The supported screen archetypes. Each maps to a design-system layout in the
/// runtime (C2). No free-form layout is permitted.
enum ScreenKind: String, Codable, Hashable, CaseIterable {
    case list        // a `PulseCard` list of entity rows
    case form        // a create/edit form for one entity record
    case detail      // a read view of one entity record
    case dashboard   // summary cards / charts
}

// MARK: - Validation

/// A single validation problem found in a spec.
struct SubAppSpecIssue: Hashable, CustomStringConvertible {
    enum Severity: String { case error, warning }
    var severity: Severity
    var path: String
    var message: String
    var description: String { "[\(severity.rawValue)] \(path): \(message)" }
}

/// Thrown when a spec fails strict validation. Carries every issue found.
struct SubAppSpecValidationError: Error, CustomStringConvertible {
    var issues: [SubAppSpecIssue]
    var description: String {
        "SubAppSpec validation failed:\n" + issues.map { "  • \($0.description)" }.joined(separator: "\n")
    }
}

/// Strict validator for `SubAppSpec`. Enforces schema compatibility, identifier
/// hygiene, referential integrity (screens point at real entities), and a few
/// design-system safety rules (icons can't be emoji, names must be slugs, etc).
enum SubAppSpecValidator {
    /// Validate `spec`. Returns all issues (errors + warnings). Does not throw.
    static func issues(in spec: SubAppSpec) -> [SubAppSpecIssue] {
        var issues: [SubAppSpecIssue] = []

        func err(_ path: String, _ message: String) {
            issues.append(.init(severity: .error, path: path, message: message))
        }
        func warn(_ path: String, _ message: String) {
            issues.append(.init(severity: .warning, path: path, message: message))
        }

        // Schema compatibility: major must match this build.
        if spec.schemaVersion.major != SubAppSpecSchema.current.major {
            err("schemaVersion",
                "incompatible schema major \(spec.schemaVersion) (this build understands \(SubAppSpecSchema.current.major).x)")
        } else if spec.schemaVersion > SubAppSpecSchema.current {
            warn("schemaVersion",
                 "spec is newer (\(spec.schemaVersion)) than this build (\(SubAppSpecSchema.current)); newer fields ignored")
        }

        // Identity.
        if !isSlug(spec.id) {
            err("id", "must be a lowercase slug (a-z, 0-9, underscore), got '\(spec.id)'")
        }
        if spec.displayName.trimmingCharacters(in: .whitespaces).isEmpty {
            err("displayName", "must not be empty")
        }
        if spec.summary.trimmingCharacters(in: .whitespaces).isEmpty {
            warn("summary", "is empty; the module picker will look bare")
        }
        if containsEmoji(spec.icon) || spec.icon.trimmingCharacters(in: .whitespaces).isEmpty {
            err("icon", "must be an SF Symbol name, never emoji or empty (got '\(spec.icon)')")
        }

        // Entities.
        var entityNames = Set<String>()
        if spec.entities.isEmpty && spec.screens.contains(where: { $0.kind != .dashboard }) {
            warn("entities", "no entities defined but non-dashboard screens exist")
        }
        for (i, entity) in spec.entities.enumerated() {
            let base = "entities[\(i)]"
            if !isSlug(entity.name) {
                err("\(base).name", "must be a lowercase slug, got '\(entity.name)'")
            }
            if !entityNames.insert(entity.name).inserted {
                err("\(base).name", "duplicate entity name '\(entity.name)'")
            }
            if entity.fields.isEmpty {
                err("\(base).fields", "entity '\(entity.name)' must have at least one field")
            }
            var fieldNames = Set<String>()
            for (j, field) in entity.fields.enumerated() {
                let fbase = "\(base).fields[\(j)]"
                if !isSlug(field.name) {
                    err("\(fbase).name", "must be a lowercase slug, got '\(field.name)'")
                }
                if !fieldNames.insert(field.name).inserted {
                    err("\(fbase).name", "duplicate field name '\(field.name)' in entity '\(entity.name)'")
                }
                if field.label.trimmingCharacters(in: .whitespaces).isEmpty {
                    warn("\(fbase).label", "empty label; forms will show the raw field name")
                }
            }
        }

        // Screens.
        if spec.screens.isEmpty {
            err("screens", "a sub-app must define at least one screen")
        }
        var screenIDs = Set<String>()
        for (i, screen) in spec.screens.enumerated() {
            let base = "screens[\(i)]"
            if !isSlug(screen.id) {
                err("\(base).id", "must be a lowercase slug, got '\(screen.id)'")
            }
            if !screenIDs.insert(screen.id).inserted {
                err("\(base).id", "duplicate screen id '\(screen.id)'")
            }
            if screen.title.trimmingCharacters(in: .whitespaces).isEmpty {
                warn("\(base).title", "empty title")
            }
            // Entity-backed screens must reference a declared entity.
            let needsEntity: Bool = (screen.kind == .list || screen.kind == .form || screen.kind == .detail)
            if needsEntity {
                guard let entity = screen.entity else {
                    err("\(base).entity", "\(screen.kind.rawValue) screen must reference an entity")
                    continue
                }
                if !entityNames.contains(entity) {
                    err("\(base).entity", "references unknown entity '\(entity)'")
                }
            } else if screen.entity != nil {
                warn("\(base).entity", "\(screen.kind.rawValue) screen ignores its 'entity' field")
            }
        }

        return issues
    }

    /// Validate strictly: throws `SubAppSpecValidationError` if any `.error`-severity
    /// issue is present. Warnings are returned via `issues(in:)` but never throw.
    static func validate(_ spec: SubAppSpec) throws {
        let found = issues(in: spec)
        let errors = found.filter { $0.severity == .error }
        if !errors.isEmpty {
            throw SubAppSpecValidationError(issues: found)
        }
    }

    /// Decode + strictly validate a spec from JSON in one step.
    static func decodeAndValidate(_ data: Data) throws -> SubAppSpec {
        let spec = try JSONDecoder().decode(SubAppSpec.self, from: data)
        try validate(spec)
        return spec
    }

    // MARK: Helpers

    /// Lowercase slug: starts with a letter, then letters/digits/underscores.
    private static func isSlug(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        let pattern = "^[a-z][a-z0-9_]*$"
        return s.range(of: pattern, options: .regularExpression) != nil
    }

    private static func containsEmoji(_ s: String) -> Bool {
        s.unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation || scalar.properties.isEmoji && scalar.value > 0x238C
        }
    }
}
