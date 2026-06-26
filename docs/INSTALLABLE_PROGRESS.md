# INSTALLABLE_PROGRESS — No Module Comes Standard

Live tracker for `docs/INSTALLABLE_MODULES_LOOP_PROMPT.md`. Status: `pending` / `in progress` / `done`.

---

## Phase A — Invert the default + migrate safely
- **A1** `done` — Unified install model on `SubAppRegistry` (`installedIDs`, `isInstalled`, `install`, `uninstall`, `installedSubApps`, `setInitial(Installed)`). Empty default; `enabledIDs`/`ModuleManager` are now aliases over `installedIDs`. `runInstallMigration()` grandfathers onboarded users (materializes "all" when no explicit set was stored) and leaves fresh installs empty. `.installedModulesChanged` notification added.
- **A2** `done` — `registerAllRoutes()` only registers installed sub-apps; re-runs on install/uninstall via `refreshAfterInstallChange()`. `SpecSubAppHost` shows an "install this module" prompt when its sub-app isn't installed.

## Phase B — First-run empty shell + unified catalog
- **B1** `done` — `ModulePickerView` is now the unified Install Catalog: iterates all registered `subApps` (built-in + spec) keyed by `SubAppID`, grouped (Core modules / Sub-apps), search field, zero pre-selected in onboarding, "Install"/"Installed" language, writes `setInitialInstalled` (onboarding) or `installedIDs` (manage) and re-registers routes.
- **B2** `done` — Home shows an "Install your first module" empty-shell card (opens the catalog full-screen) when `installedIDs` is empty; collection cards already gate on install state. First-run catalog presentation unchanged but now starts empty by default.

## Phase C — Make every surface install-aware
- **C1** `done` — `BottomNavBar` derives tabs from install state: Home/Tracker/Ask AI are fixed anchors; Inbox (`aiCapture`) and Friends (`accountability`) hide when uninstalled; recomputes on `.installedModulesChanged`; falls back to Home if the selected tab was uninstalled.
- **C2** `done` — `HomeView` collection cards already gate on `isEnabled`; added an "Install your first module" empty-shell card (opens the catalog) when nothing is installed.
- **C3** `done` — Sidebar collections (Notes/Tasks/Protocol/Journal/Fitness) and social (Accountability) rows now gate on install state; Profile + Settings/Modules stay core.
- **C4** `done` — `SubAppRegistry.aiTools(flags:)` merges installed sub-apps only. `list_modules`/`set_module_enabled` now speak install/uninstall (install immediate, uninstall confirmed + data-preserving), built-ins included; `save_subapp` uses `install()`. `PendingActionExecutor.disableModule` calls `uninstall()`. System prompt teaches the brain the "no module comes standard" model.

## Phase D — Unify built-in/spec/registry + uninstall semantics
- **D1** `done` — Registry install (`SubAppRegistryView`), import (`MySubAppsView`), Builder save, Editor save, and `save_subapp` all call `SubAppRegistry.install(_:)` so a sub-app surfaces everywhere via the one `installedIDs` model. `MySubAppsView.open` installs before navigating; delete uninstalls. Built-ins are uninstallable through the same model/tools.
- **D2** `done` — Uninstall hides + preserves data (`.disableModule` → `uninstall()`). New `.removeModuleData` PendingAction + `remove_module_data` Coach tool wipe a spec sub-app's `DynamicSubAppRecord` data via `deleteAll(subAppID:)` after confirmation; styled destructive. System prompt teaches install/uninstall + data-preservation.

## Phase E — Polish + hardening
- **E1** `done` — Catalog UX delivered during B1: search field, Core/Sub-apps grouping, per-module accent + "Install"/"Installed" badges, accessibility labels/traits on cards. Install/uninstall reflected immediately via `.installedModulesChanged`.
- **E2** `done` — `PulseLoopTests/InstallModelTests.swift` (10 tests, all green): fresh-install empties, install/uninstall state flips, migration grandfathers onboarded users / leaves fresh empty / preserves explicit selection, `list_modules` reports install state, `set_module_enabled` install-immediate vs uninstall-confirms, `aiTools` only from installed sub-apps, uninstall preserves spec data + reinstall restores, `remove_module_data` wipes spec records. Full suite `** TEST SUCCEEDED **`.

---

### Log
- (init) Tracker created from roadmap.
- Phases A–D implemented across `SubAppRegistry`, catalog, surfaces (tabs/home/sidebar), Coach tools, and uninstall/remove-data semantics.
- Phase E: confirmed catalog UX/a11y from B1; added `InstallModelTests` (10/10 pass) and verified full test suite green. Roadmap complete.
