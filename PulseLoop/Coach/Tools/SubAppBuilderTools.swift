import Foundation
import SwiftData
import Combine

// MARK: - Sub-App Builder Coach Tools (roadmap D1)
//
// Two tools let the Coach author and refine declarative `SubAppSpec`s from a natural-
// language description. The model fills a strict JSON schema (mirroring `SubAppSpec`),
// the tool decodes + strictly validates it via `SubAppSpecValidator`, and on success
// stages it as a draft in `SubAppBuilderDraftStore`. The Builder UI (D2) reads the
// draft to preview, refine, and save it as a `.userCreated` SubApp. Validation /
// permission / design-system guardrails are enforced here and expanded in D3.

@MainActor
enum SubAppBuilderTools {
    static var all: [AnyCoachTool] { [generateSpec, refineSpec] }

    // MARK: Shared JSON schema for a spec

    /// Strict JSON schema describing a `SubAppSpec`. Kept in lockstep with
    /// `SubAppSpec`/`EntitySpec`/`FieldSpec`/`ScreenSpec`.
    private static var specSchema: [String: Any] {
        let fieldSchema = JSONSchema.object([
            "name": JSONSchema.string,
            "label": JSONSchema.string,
            "type": JSONSchema.enumString(FieldType.allCases.map { $0.rawValue }),
            "required": JSONSchema.boolean,
            "options": JSONSchema.array(JSONSchema.string),
        ], required: ["name", "label", "type", "required", "options"])

        let entitySchema = JSONSchema.object([
            "name": JSONSchema.string,
            "label": JSONSchema.string,
            "fields": JSONSchema.array(fieldSchema),
        ], required: ["name", "label", "fields"])

        let screenSchema = JSONSchema.object([
            "id": JSONSchema.string,
            "title": JSONSchema.string,
            "kind": JSONSchema.enumString(ScreenKind.allCases.map { $0.rawValue }),
            "entity": JSONSchema.string,
        ], required: ["id", "title", "kind", "entity"])

        return JSONSchema.object([
            "id": JSONSchema.string,
            "display_name": JSONSchema.string,
            "icon": JSONSchema.string,
            "summary": JSONSchema.string,
            "permissions": JSONSchema.array(JSONSchema.enumString(SubAppPermission.allCases.map { $0.rawValue })),
            "entities": JSONSchema.array(entitySchema),
            "screens": JSONSchema.array(screenSchema),
        ], required: ["id", "display_name", "icon", "summary", "permissions", "entities", "screens"])
    }

    private static let guidance = """
    Author a SubAppSpec for a small personal-tracking sub-app.
    Rules (validation will reject violations):
    - `id`, every entity/field `name`, and every screen `id` must be lowercase slugs \
    (start with a letter; only a-z, 0-9, underscore).
    - `icon` must be an SF Symbol name (e.g. "drop.fill"), NEVER an emoji.
    - Field `type` is one of: text, number, integer, boolean, date, rating, selection. \
    For `selection` fields, put the choices in `options` (empty array otherwise).
    - Every list/form/detail screen must set `entity` to a declared entity name. \
    A dashboard screen sets `entity` to "" (it ignores it).
    - Prefer one entity with 2-5 fields and screens: a list, a form, optionally a \
    detail, and optionally a dashboard. The first screen is the entry point.
    - Only request `permissions` the sub-app truly needs.
    """

    // MARK: generate_subapp_spec

    private static var generateSpec: AnyCoachTool {
        .make(
            name: "generate_subapp_spec",
            label: "Designing a sub-app",
            description: "Generate a new declarative SubAppSpec from a description of what the user wants to track. \(guidance) Returns the validated spec (and any warnings); it is staged as a draft for the Builder UI to preview.",
            parameters: specSchema,
            argsType: SpecArgs.self
        ) { args, _ in
            handle(args, isRefinement: false)
        }
    }

    // MARK: refine_subapp_spec

    private static var refineSpec: AnyCoachTool {
        .make(
            name: "refine_subapp_spec",
            label: "Refining a sub-app",
            description: "Refine the current draft SubAppSpec. Provide the FULL updated spec (not a diff). \(guidance) Returns the validated spec; it replaces the staged draft.",
            parameters: specSchema,
            argsType: SpecArgs.self
        ) { args, _ in
            handle(args, isRefinement: true)
        }
    }

    // MARK: Handler

    private static func handle(_ args: SpecArgs, isRefinement: Bool) -> ToolResult {
        var spec = args.toSpec()
        // Conversational edits bump the version so each refinement is a distinct,
        // ordered revision (mirrors the editor's patch bump). Base off the prior
        // staged draft (or an already-installed module of the same id) so versions
        // climb across a multi-turn refine conversation.
        spec.version = bumpedVersion(for: spec, isRefinement: isRefinement)
        let issues = SubAppSpecValidator.issues(in: spec)
        let errors = issues.filter { $0.severity == .error }
        guard errors.isEmpty else {
            return .error("spec is invalid:\n" + errors.map { "• \($0.description)" }.joined(separator: "\n"))
        }
        // Policy guardrails (size limits, reserved ids, content safety).
        let report = SubAppGuardrails.review(spec)
        guard report.canSave else {
            return .error("spec violates guardrails:\n" + report.blockers.map { "• \($0.description)" }.joined(separator: "\n"))
        }
        SubAppBuilderDraftStore.shared.stage(spec)
        let warnings = (issues.filter { $0.severity == .warning } + report.warnings).map { $0.message }
        return .object([
            "ok": true,
            "action": isRefinement ? "refined" : "generated",
            "spec_id": spec.id,
            "display_name": spec.displayName,
            "version": spec.version.description,
            "entity_count": spec.entities.count,
            "screen_count": spec.screens.count,
            "permissions": report.permissionsToReview.map { $0.rawValue },
            "warnings": warnings,
            "note": "Draft staged (v\(spec.version)). When the design is right, call save_subapp to show the user a live preview with an Install button.",
        ])
    }

    /// The version to stamp on a (re)staged draft. A fresh generation starts at the
    /// model-provided version (default 1.0.0). A refinement bumps the patch over the
    /// highest known prior version for this id: the current staged draft, or an
    /// installed module of the same id. Pure given the two stores' current state.
    static func bumpedVersion(for spec: SubAppSpec, isRefinement: Bool) -> SemanticVersion {
        guard isRefinement else { return spec.version }
        var base = spec.version
        if let staged = SubAppBuilderDraftStore.shared.draft, staged.id == spec.id, staged.version > base {
            base = staged.version
        }
        if let installed = UserSubAppStore.shared.specs.first(where: { $0.id == spec.id }), installed.version > base {
            base = installed.version
        }
        return SemanticVersion(major: base.major, minor: base.minor, patch: base.patch + 1)
    }

    // MARK: Decodable args (snake_case mirror of SubAppSpec)

    private struct SpecArgs: Decodable {
        let id: String
        let displayName: String
        let icon: String
        let summary: String
        let permissions: [String]
        let entities: [EntityArgs]
        let screens: [ScreenArgs]

        enum CodingKeys: String, CodingKey {
            case id, icon, summary, permissions, entities, screens
            case displayName = "display_name"
        }

        func toSpec() -> SubAppSpec {
            SubAppSpec(
                id: id,
                displayName: displayName,
                icon: icon,
                summary: summary,
                author: "User",
                permissions: permissions.compactMap { SubAppPermission(rawValue: $0) },
                entities: entities.map { $0.toEntity() },
                screens: screens.map { $0.toScreen() }
            )
        }
    }

    private struct EntityArgs: Decodable {
        let name: String
        let label: String
        let fields: [FieldArgs]
        func toEntity() -> EntitySpec {
            EntitySpec(name: name, label: label, fields: fields.map { $0.toField() })
        }
    }

    private struct FieldArgs: Decodable {
        let name: String
        let label: String
        let type: String
        let required: Bool
        let options: [String]
        func toField() -> FieldSpec {
            FieldSpec(
                name: name,
                label: label,
                type: FieldType(rawValue: type) ?? .text,
                required: required,
                options: options
            )
        }
    }

    private struct ScreenArgs: Decodable {
        let id: String
        let title: String
        let kind: String
        let entity: String
        func toScreen() -> ScreenSpec {
            ScreenSpec(
                id: id,
                title: title,
                kind: ScreenKind(rawValue: kind) ?? .list,
                entity: entity.isEmpty ? nil : entity
            )
        }
    }
}

// MARK: - Draft store

/// Holds the single in-progress spec draft produced by the Builder tools. The
/// Builder UI (D2) observes this to preview/refine before saving as a real
/// `.userCreated` SubApp.
@MainActor
final class SubAppBuilderDraftStore: ObservableObject {
    static let shared = SubAppBuilderDraftStore()
    private init() {}

    @Published private(set) var draft: SubAppSpec?

    func stage(_ spec: SubAppSpec) { draft = spec }
    func clear() { draft = nil }
}

// MARK: - User spec persistence

/// Persists `.userCreated` (and later `.installed`) specs as JSON so they survive
/// launches. Saved specs are loaded into `SpecSubAppCatalog` + `SubAppRegistry` at
/// startup so they behave like any other sub-app.
@MainActor
final class UserSubAppStore: ObservableObject {
    static let shared = UserSubAppStore()

    private static let storageKey = "pulseloop.subapps.userCreated.v1"
    private static let originsKey = "pulseloop.subapps.origins.v1"
    private let defaults: UserDefaults

    @Published private(set) var specs: [SubAppSpec] = []
    /// Origin per saved spec id. Specs authored in the Builder are `.userCreated`;
    /// those installed from the sharing gallery are `.installed` (so attribution and
    /// trust decisions hold). Legacy entries with no recorded origin default to
    /// `.userCreated`.
    @Published private(set) var origins: [String: SubAppOrigin] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    private func load() {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([SubAppSpec].self, from: data) else {
            specs = []
            return
        }
        specs = decoded
        if let originData = defaults.data(forKey: Self.originsKey),
           let decodedOrigins = try? JSONDecoder().decode([String: SubAppOrigin].self, from: originData) {
            origins = decodedOrigins
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(specs) else { return }
        defaults.set(data, forKey: Self.storageKey)
        if let originData = try? JSONEncoder().encode(origins) {
            defaults.set(originData, forKey: Self.originsKey)
        }
    }

    /// The recorded origin for a saved spec id (defaults to `.userCreated`).
    func origin(for id: String) -> SubAppOrigin { origins[id] ?? .userCreated }

    /// Save (insert or replace by id) a validated spec with an explicit origin.
    func save(_ spec: SubAppSpec, origin: SubAppOrigin = .userCreated) {
        if let idx = specs.firstIndex(where: { $0.id == spec.id }) {
            specs[idx] = spec
        } else {
            specs.append(spec)
        }
        origins[spec.id] = origin
        persist()
        SpecSubAppCatalog.shared.register(spec)
    }

    func delete(id: String) {
        specs.removeAll { $0.id == id }
        origins.removeValue(forKey: id)
        persist()
    }
}
