import SwiftUI
import SwiftData

// MARK: - SubApp Platform Primitives
//
// A `SubApp` is the self-contained unit of functionality the platform is built
// around. The long-term goal (see docs/LOOP_PROMPT.md) is for every feature —
// Sleep, Activity, Tasks, Notes, etc. — to be expressed as a `SubApp` so it stops
// coupling to the three centralization points (routing, the SwiftData schema, and
// the Coach tool registry). This file introduces the protocol + supporting types.
// It is deliberately additive: nothing yet *requires* features to conform, and the
// registry mirrors the existing `ModuleManager` enable/disable storage so behavior
// is unchanged.

/// Where a sub-app came from. Drives trust/permission decisions later.
enum SubAppOrigin: String, Codable, Hashable {
    /// Ships with the app, written in Swift.
    case builtIn
    /// Authored by the user via the AI Sub-App Builder (declarative spec).
    case userCreated
    /// Installed from the sharing registry (declarative spec).
    case installed
}

/// Capabilities a sub-app may request. Used for permission review of installed /
/// user-created sub-apps and for surfacing what a sub-app can touch.
enum SubAppPermission: String, Codable, Hashable, CaseIterable {
    case healthRead
    case healthWrite
    case notifications
    case network
    case camera
    case microphone
    case location
}

/// A stable identifier for a sub-app. For built-ins this mirrors the legacy
/// `AppModule.rawValue` so enable/disable state migrates cleanly.
struct SubAppID: RawRepresentable, Hashable, Codable, ExpressibleByStringLiteral, Identifiable {
    let rawValue: String
    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }
    init(stringLiteral value: String) { self.rawValue = value }
    var id: String { rawValue }
}

// MARK: - Changelog (Experience loop P2)

/// A single released version of a sub-app with its human-readable notes. Drives
/// the "Version history" section of `ModuleDetailView` so users can see what
/// changed across versions and make an informed update decision.
struct SubAppChangelogEntry: Hashable, Codable, Identifiable {
    /// The released version (newest entries should sort first for display).
    let version: SemanticVersion
    /// Short, user-facing bullet notes describing what changed in this version.
    let notes: [String]
    /// Optional ISO-8601 / display date string ("2026-06" or "Jun 2026"). Free-form.
    let date: String?

    var id: String { version.description }

    init(version: SemanticVersion, notes: [String], date: String? = nil) {
        self.version = version
        self.notes = notes
        self.date = date
    }

    /// Convenience for built-ins that hand-author entries with a version string.
    init(_ version: String, _ notes: [String], date: String? = nil) {
        self.version = SemanticVersion.parseOrDefault(version)
        self.notes = notes
        self.date = date
    }
}

/// The protocol every feature module conforms to. Built-in sub-apps implement this
/// directly in Swift; user-created / installed sub-apps are produced by a runtime
/// that interprets a declarative spec (added in a later phase) and conforms on
/// their behalf.
///
/// Conformers contribute their pieces to the platform rather than wiring into the
/// central `AppRoute` / `Schema` / `ToolRegistry` directly. During the migration,
/// most members have safe defaults so a feature can adopt the protocol incrementally.
protocol SubApp {
    /// Stable identity (mirrors `AppModule.rawValue` for built-ins).
    var id: SubAppID { get }

    /// Human-facing name shown in pickers and the sidebar.
    var displayName: String { get }

    /// SF Symbol (never emoji — see design-system rule) used on cards and pickers.
    var iconSystemName: String { get }

    /// One-line description for the module picker.
    var summary: String { get }

    /// Semantic version of this sub-app's definition.
    var version: String { get }

    /// Released-version history, newest first, for the detail screen's "What's new"
    /// / version history. Default is a single synthesized entry from `version` so
    /// every module shows at least its current release. Built-ins override with
    /// hand-authored notes; spec sub-apps derive theirs from the spec.
    var changelog: [SubAppChangelogEntry] { get }

    /// Author/owner string (e.g. "PulseLoop" for built-ins).
    var author: String { get }

    /// Provenance — drives trust + permission handling.
    var origin: SubAppOrigin { get }

    /// SwiftData models this sub-app contributes to the container schema.
    /// (Wired into `ModelContainerFactory` in iteration A4.)
    var models: [any PersistentModel.Type] { get }

    /// Permissions this sub-app needs.
    var permissions: Set<SubAppPermission> { get }

    /// Contribute navigation destinations to the shared router. Default is a no-op;
    /// sub-apps that own pushable screens register them here (see `SubAppRouter`).
    @MainActor
    func registerRoutes(with router: SubAppRouter)

    /// Coach AI tools this sub-app contributes, gated by the coach feature flags.
    /// Default is none. Returned tools are merged into the central `ToolRegistry`
    /// (see iteration A5). Built-in sub-apps that own a domain register their
    /// retrieval/action tools here as they migrate in Phase B.
    @MainActor
    func aiTools(flags: CoachFeatureFlags) -> [AnyCoachTool]

    /// Optional Home dashboard card for this sub-app. Default is `nil` (no card).
    /// The `context` carries the navigation path so the card can deep-link into the
    /// sub-app. Cards must use design-system components (`PulseCard`, `PulseColors`,
    /// `PulseFont`) — see `.cursor/rules/design-system.mdc`.
    @MainActor
    func dashboardCard(context: RouteContext) -> AnyView?

    /// Forward-migrate this module's stored data when the user updates from an older
    /// installed version to a newer one. Default is a no-op (most version bumps are
    /// UI-only). Migrations MUST be data-preserving — never delete user records.
    @MainActor
    func migrate(from oldVersion: SemanticVersion, to newVersion: SemanticVersion, context: ModelContext)

    /// Whether updating from `oldVersion` to `newVersion` should be confirmed before
    /// it runs (e.g. it rewrites data irreversibly). Default is `false` — most updates
    /// are UI-only and apply silently. This is a pure query: it must not mutate data.
    @MainActor
    func updateNeedsConfirmation(from oldVersion: SemanticVersion, to newVersion: SemanticVersion) -> Bool
}

// MARK: - Defaults

extension SubApp {
    var version: String { "1.0.0" }
    var author: String { "PulseLoop" }
    var origin: SubAppOrigin { .builtIn }
    var models: [any PersistentModel.Type] { [] }
    var permissions: Set<SubAppPermission> { [] }

    /// Default changelog: a single entry for the current version. Modules with real
    /// history override this. Sorted newest-first by the detail view regardless.
    var changelog: [SubAppChangelogEntry] {
        [SubAppChangelogEntry(version: semanticVersion, notes: ["Current release."], date: nil)]
    }

    /// The module's `version` string normalized to a comparable `SemanticVersion`
    /// (tolerant — malformed strings fall back to `1.0.0`). This is the value the
    /// update system compares against the stored installed version.
    var semanticVersion: SemanticVersion { SemanticVersion.parseOrDefault(version) }

    @MainActor
    func registerRoutes(with router: SubAppRouter) {}

    @MainActor
    func aiTools(flags: CoachFeatureFlags) -> [AnyCoachTool] { [] }

    @MainActor
    func dashboardCard(context: RouteContext) -> AnyView? { nil }

    /// Default: nothing to migrate.
    @MainActor
    func migrate(from oldVersion: SemanticVersion, to newVersion: SemanticVersion, context: ModelContext) {}

    /// Default: updates apply silently.
    @MainActor
    func updateNeedsConfirmation(from oldVersion: SemanticVersion, to newVersion: SemanticVersion) -> Bool { false }
}
