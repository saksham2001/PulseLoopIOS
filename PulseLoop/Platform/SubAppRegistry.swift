import SwiftUI
import SwiftData

// MARK: - SubAppRegistry
//
// Central discovery + enable/disable state for sub-apps. This is the seam that
// will eventually feed models → `ModelContainerFactory`, routes → the router, and
// tools → the Coach `ToolRegistry`. For now (iteration A2) it only knows about the
// built-in sub-apps that mirror the legacy `AppModule` cases, and it owns the
// enable/disable storage so `ModuleManager` can delegate to it without any behavior
// change. The UserDefaults keys are intentionally identical to the legacy ones so
// existing installs keep their saved module selection.

/// A built-in sub-app backed 1:1 by a legacy `AppModule`. As features migrate to
/// real `SubApp` conformers (Phase B) these get replaced one at a time.
struct BuiltInModuleSubApp: SubApp {
    let module: AppModule

    var id: SubAppID { SubAppID(module.rawValue) }
    var displayName: String { module.name }
    var iconSystemName: String { module.icon }
    var summary: String { module.description }
    var origin: SubAppOrigin { .builtIn }
}

final class SubAppRegistry {
    static let shared = SubAppRegistry()

    // Storage keys mirror the legacy `ModuleManager` so saved state migrates.
    private let enabledKey = "enabledModules"
    private let hasOnboardedKey = "hasCompletedModuleOnboarding"
    /// Installed-version ledger: maps `SubAppID.rawValue` → the module version string
    /// active when the user installed/last-updated it. Drives `availableUpdate(for:)`.
    /// Mirrors `SubAppRegistryStore.installedVersions` but covers ALL modules
    /// (built-in + spec), so versioning is uniform across the platform.
    private let installedVersionsKey = "pulseloop.modules.installedVersions.v1"
    /// One-time backfill marker so existing installs don't all show "update available".
    private let versionBackfillKey = "pulseloop.modules.versionBackfill.v1"
    /// Marks that the "no module comes standard" migration has run. Once set, an
    /// absent `enabledModules` value means "nothing installed" (empty) rather than
    /// the legacy "all installed" default.
    private let installMigrationKey = "installModel_noStandardModules_v1"

    /// All registered sub-apps. Currently the built-in module set; user-created /
    /// installed sub-apps will be appended here in later phases.
    private(set) var subApps: [any SubApp]

    private init() {
        // Built-in sub-apps. Features migrated to real `SubApp` conformers (Phase B)
        // are substituted for their generic `BuiltInModuleSubApp` placeholder here,
        // one per iteration.
        let migrated: [AppModule: any SubApp] = [
            .sleep: SleepSubApp(),
            .workouts: FitnessSubApp(),
            .protocol_: ProtocolSubApp(),
            .nutrition: NutritionSubApp(),
            .tasks: TasksSubApp(),
            .notes: NotesSubApp(),
            .moodTracking: MoodSubApp(),
                .quitProgram: QuitProgramSubApp(),
                .accountability: FriendsSubApp(),
                .aiCapture: InboxSubApp(),
                .dayPlan: DayPlanSubApp(),
                .travel: TravelSubApp(),
        ]
        let moduleBacked: [any SubApp] = AppModule.allCases.map { module in
            migrated[module] ?? BuiltInModuleSubApp(module: module)
        }
        // Built-in sub-apps that don't map onto a legacy `AppModule` (e.g. cardio
        // Activity, which is reached from Health rather than the module picker).
        let extras: [any SubApp] = [
            ActivitySubApp(),
            HealthSubApp(),
            JournalSubApp(),
            StressSubApp(),
            MeditationSubApp(),
            SymptomsLabsSubApp(),
            // Spec-driven sub-apps (C4 proves the runtime with a built-in Mood spec;
            // user-created / installed specs are appended here in Phases D & F).
            SpecSubApp(spec: BuiltInSpecs.moodCheckIn),
        ]
        self.subApps = moduleBacked + extras
    }

    // MARK: Lookup

    func subApp(id: SubAppID) -> (any SubApp)? {
        subApps.first { $0.id == id }
    }

    /// Register navigation destinations for **installed** sub-apps with the shared
    /// router. Called at app startup and again on any install/uninstall so deep-links
    /// only resolve for modules the user actually has. Built-in module routes still
    /// live in the central `AppRoute` switch (guarded there); this is the seam for
    /// `SubApp` conformers (e.g. spec sub-apps).
    @MainActor
    func registerAllRoutes() {
        loadUserSpecs()
        let installed = installedIDs
        for app in subApps where installed.contains(app.id) {
            app.registerRoutes(with: SubAppRouter.shared)
        }
    }

    /// Load persisted user-created spec sub-apps from `UserSubAppStore` into the
    /// registry + spec catalog. Idempotent — replaces any existing user-created
    /// entries. Called at startup and after the Builder saves a new sub-app.
    @MainActor
    func loadUserSpecs() {
        subApps.removeAll { $0.origin == .userCreated || $0.origin == .installed }
        for spec in UserSubAppStore.shared.specs {
            SpecSubAppCatalog.shared.register(spec)
            let origin = UserSubAppStore.shared.origin(for: spec.id)
            subApps.append(SpecSubApp(spec: spec, origin: origin))
        }
    }

    /// Models contributed by all registered sub-apps. Wired into the schema in A4.
    var allModels: [any PersistentModel.Type] {
        subApps.flatMap { $0.models }
    }

    /// Coach AI tools contributed by **installed** sub-apps for the given flags.
    /// Uninstalled modules contribute no tools, so the brain can't act on a feature
    /// the user hasn't installed. Merged into the central `ToolRegistry`.
    @MainActor
    func aiTools(flags: CoachFeatureFlags) -> [AnyCoachTool] {
        let installed = installedIDs
        return subApps
            .filter { installed.contains($0.id) }
            .flatMap { $0.aiTools(flags: flags) }
    }

    // MARK: Install / enable state
    //
    // "Installed" is the single gate for whether a module is present in the app. We
    // collapse the legacy enable/disable concept into install/uninstall: an installed
    // sub-app is enabled, an uninstalled one is absent everywhere (tabs, Home,
    // sidebar, routes, Coach tools, settings). `enabledIDs` remains as a back-compat
    // alias over the same storage so `ModuleManager` keeps working.

    var hasOnboarded: Bool {
        get { UserDefaults.standard.bool(forKey: hasOnboardedKey) }
        set { UserDefaults.standard.set(newValue, forKey: hasOnboardedKey) }
    }

    /// The set of installed sub-app IDs — the single source of truth for module
    /// presence. **No module comes standard:** a fresh install (no persisted value,
    /// post-migration) returns an EMPTY set. The legacy "absent ⇒ all enabled"
    /// default is gone; existing users are grandfathered by `runInstallMigration()`.
    var installedIDs: Set<SubAppID> {
        get {
            guard let data = UserDefaults.standard.data(forKey: enabledKey),
                  let ids = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return Set(ids.map { SubAppID($0) })
        }
        set {
            let ids = newValue.map { $0.rawValue }
            if let data = try? JSONEncoder().encode(ids) {
                UserDefaults.standard.set(data, forKey: enabledKey)
            }
        }
    }

    /// Back-compat alias. Older call sites (and the `ModuleManager` bridge) talk in
    /// terms of "enabled"; install == enable in the unified model.
    var enabledIDs: Set<SubAppID> {
        get { installedIDs }
        set { installedIDs = newValue }
    }

    /// Registered sub-apps that the user has installed. This is what every render
    /// surface should iterate — never the full `subApps` list.
    var installedSubApps: [any SubApp] {
        let installed = installedIDs
        return subApps.filter { installed.contains($0.id) }
    }

    func isInstalled(_ id: SubAppID) -> Bool { installedIDs.contains(id) }
    func isEnabled(_ id: SubAppID) -> Bool { isInstalled(id) }

    // MARK: Installed-version ledger (uniform per-module versioning)

    /// Raw `SubAppID.rawValue` → installed version string. Persisted to UserDefaults.
    private var installedVersions: [String: String] {
        get {
            guard let data = UserDefaults.standard.data(forKey: installedVersionsKey),
                  let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
                return [:]
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: installedVersionsKey)
            }
        }
    }

    /// The version recorded when the user installed/last-updated this module, if any.
    func installedVersion(of id: SubAppID) -> SemanticVersion? {
        installedVersions[id.rawValue].flatMap(SemanticVersion.init)
    }

    /// Record the given version as the installed version for a module.
    func recordInstalledVersion(_ id: SubAppID, _ version: SemanticVersion) {
        var current = installedVersions
        current[id.rawValue] = version.description
        installedVersions = current
    }

    /// Record a module's *current build* version as installed (used on install).
    private func recordCurrentVersion(_ id: SubAppID) {
        guard let app = subApp(id: id) else { return }
        recordInstalledVersion(id, app.semanticVersion)
    }

    /// One-time backfill: stamp every already-installed module with its current build
    /// version so upgrading to the versioning feature doesn't show spurious updates.
    func runVersionBackfill() {
        guard !UserDefaults.standard.bool(forKey: versionBackfillKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: versionBackfillKey) }
        var current = installedVersions
        for app in installedSubApps where current[app.id.rawValue] == nil {
            current[app.id.rawValue] = app.semanticVersion.description
        }
        installedVersions = current
    }

    // MARK: Update detection + apply

    /// The newer version available for an installed module, or nil if up to date.
    /// "Available" = the running build's `SubApp.version` is greater than the version
    /// recorded when the user installed/last-updated the module.
    func availableUpdate(for id: SubAppID) -> SemanticVersion? {
        guard isInstalled(id), let app = subApp(id: id) else { return nil }
        let current = app.semanticVersion
        // No recorded version (e.g. pre-ledger install that missed backfill) ⇒ stamp
        // it as current so we don't show a false update.
        guard let installed = installedVersion(of: id) else {
            recordInstalledVersion(id, current)
            return nil
        }
        return current > installed ? current : nil
    }

    /// Installed modules that have a newer version available in this build.
    var modulesWithUpdates: [any SubApp] {
        installedSubApps.filter { availableUpdate(for: $0.id) != nil }
    }

    /// Whether the available update for a module wants explicit confirmation before
    /// it runs (pure query — does not mutate data).
    @MainActor
    func updateNeedsConfirmation(_ id: SubAppID) -> Bool {
        guard let target = availableUpdate(for: id), let app = subApp(id: id) else { return false }
        let from = installedVersion(of: id) ?? SemanticVersion(major: 1, minor: 0, patch: 0)
        return app.updateNeedsConfirmation(from: from, to: target)
    }

    /// Apply the available update for a module: run its forward migration (data-
    /// preserving) then record the new installed version. Returns the version applied,
    /// or nil if there was nothing to update.
    @discardableResult
    @MainActor
    func applyUpdate(_ id: SubAppID, context: ModelContext) -> SemanticVersion? {
        guard let target = availableUpdate(for: id), let app = subApp(id: id) else { return nil }
        let from = installedVersion(of: id) ?? SemanticVersion(major: 1, minor: 0, patch: 0)
        app.migrate(from: from, to: target, context: context)
        recordInstalledVersion(id, target)
        NotificationCenter.default.post(name: .installedModulesChanged, object: nil)
        return target
    }

    /// Apply a self-improvement (T5): run the (reloaded) module's forward migration
    /// from `from` to `to` and stamp the new installed version. The spec must already
    /// be saved + reloaded so `subApp(id:)` returns the new shape. Data-preserving for
    /// additive changes; the module's `migrate` hook handles anything bespoke.
    @MainActor
    func applyImprovedVersion(_ id: SubAppID, from: SemanticVersion, to: SemanticVersion, context: ModelContext) {
        if let app = subApp(id: id) {
            app.migrate(from: from, to: to, context: context)
        }
        recordInstalledVersion(id, to)
        NotificationCenter.default.post(name: .installedModulesChanged, object: nil)
    }

    @MainActor
    func install(_ id: SubAppID) {
        guard !isInstalled(id) else { return }
        var current = installedIDs
        current.insert(id)
        installedIDs = current
        recordCurrentVersion(id)
        refreshAfterInstallChange()
    }

    /// Uninstall HIDES the module everywhere and removes it from the installed set.
    /// It does NOT delete the user's underlying SwiftData records — reinstalling
    /// restores them. A separate, confirmed "remove data too" path handles wipes.
    @MainActor
    func uninstall(_ id: SubAppID) {
        guard isInstalled(id) else { return }
        var current = installedIDs
        current.remove(id)
        installedIDs = current
        var versions = installedVersions
        versions.removeValue(forKey: id.rawValue)
        installedVersions = versions
        refreshAfterInstallChange()
    }

    func setEnabled(_ id: SubAppID, _ enabled: Bool) {
        var current = installedIDs
        if enabled { current.insert(id) } else { current.remove(id) }
        installedIDs = current
    }

    func toggle(_ id: SubAppID) {
        setEnabled(id, !isInstalled(id))
    }

    func setInitial(_ ids: Set<SubAppID>) {
        installedIDs = ids
        hasOnboarded = true
    }

    /// First-run install selection (alias of `setInitial`) — clearer intent at the
    /// catalog call site.
    func setInitialInstalled(_ ids: Set<SubAppID>) {
        setInitial(ids)
    }

    /// One-time migration for the "no module comes standard" change. Before this,
    /// an absent `enabledModules` value meant "all enabled". To avoid emptying the
    /// app for users who already onboarded, we grandfather them: if they have any
    /// persisted module selection OR have completed module onboarding, we keep their
    /// current set (materializing "all" into an explicit set when nothing is stored).
    /// Genuinely fresh installs fall through to the new empty default.
    func runInstallMigration() {
        guard !UserDefaults.standard.bool(forKey: installMigrationKey) else { return }
        defer { UserDefaults.standard.set(true, forKey: installMigrationKey) }

        let hasPersistedSelection = UserDefaults.standard.data(forKey: enabledKey) != nil
        let alreadyOnboarded = UserDefaults.standard.bool(forKey: hasOnboardedKey)

        if hasPersistedSelection {
            // They have an explicit set already — installedIDs reads it as-is. Nothing to do.
            return
        }
        if alreadyOnboarded {
            // Onboarded under the old "all enabled" default but never persisted a set.
            // Materialize "all currently registered" as their installed set so the
            // upgrade preserves their app.
            installedIDs = Set(subApps.map { $0.id })
        }
        // Fresh install (not onboarded, no selection): leave empty — nothing installed.
    }

    /// Hook to refresh install-aware surfaces after an install/uninstall. Re-registers
    /// routes and broadcasts a notification observers can react to.
    @MainActor
    private func refreshAfterInstallChange() {
        registerAllRoutes()
        NotificationCenter.default.post(name: .installedModulesChanged, object: nil)
    }
}
