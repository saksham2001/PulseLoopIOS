# PulseLoop → Fully Installable Modules ("No Module Comes Standard") — Loop Prompt

> **How to use this file.** Paste the section titled **"THE LOOP PROMPT"** (§4) into Claude (Cursor agent) as a single message at the start of each working session. Claude does exactly one iteration, updates the tracker `docs/INSTALLABLE_PROGRESS.md`, and stops. Re-run to advance. The rest of this document (Context, Roadmap, Guardrails) is reference the prompt points Claude at — keep it in the repo.

---

## 0. North-Star Vision (the fixed mission — never changes between iterations)

**Make every module an app the user installs, not a feature that ships on.** PulseLoop should behave like a personal app store: the shell is nearly empty until the user *chooses* to install modules. **No module — not even pre-existing built-ins like Sleep, Activity, Tasks, Notes, Protocol, Mood, Friends — comes standard.** On first run the user is presented with the full catalog and installs exactly what they want; everything else stays uninstalled and invisible. An uninstalled module must not clutter the app: no tab, no Home card, no router destination, no Coach tools, no settings rows, and (ideally) no schema/seed footprint surfaced to the user.

**The end state:** open a fresh install → see a clean shell + an install catalog → pick a few modules → only those appear anywhere in the app. Visit the catalog later → install/uninstall any module (built-in or spec-driven) at will, with installed state persisted and reversible.

**Core principle: "installed" is the single gate.** Today the platform has an `enabledIDs` set that *defaults to "all enabled"* and onboarding that seeds everything. We invert this: the default is **empty** (nothing installed), and every surface that renders a module first asks "is this installed?". Built-in sub-apps and spec/registry sub-apps flow through **one** install model.

**Non-negotiables across every iteration:**
- The app must **always build and run** at the end of each iteration. Never leave the working tree broken.
- **Design system is law.** Every screen uses `PulseColors` / `PulseFont` / `PulseRadius` / `PulseLayout` and components from `App/AppTheme.swift` + `DesignSystem/Components.swift`. Follow `.cursor/rules/design-system.mdc`. **SF Symbols only, no emoji in rendered UI. Primary buttons are black, accent used sparingly.**
- **Backward-compatible data.** SwiftData migrations are additive/lightweight. **Never drop user data.** Uninstalling a module hides it and its entry points; it must NOT delete the user's underlying records unless the user explicitly confirms a destructive "remove data too" path through the `PendingAction` confirm-card flow.
- **Existing installs must not lose their setup.** A one-time migration treats already-onboarded users' current `enabledIDs` as their installed set, so upgrading doesn't suddenly empty their app. Only genuinely fresh installs start empty.
- **Reversible by default.** Install and uninstall are both one tap and fully reversible (data preserved). Destructive data removal is a separate, confirmed action.
- **One source of truth.** All "is this module present?" checks go through the installed-state API on `SubAppRegistry`; no scattered `AppModule.allCases` rendering that ignores install state.

---

## 1. Codebase Context (real anchors — verified; do not invent file names)

**Stack:** SwiftUI + SwiftData. Entry `PulseLoop/PulseLoopApp.swift` → `RootAppView` (`Views/RootViews.swift`). Profile-gated onboarding: `RootAppView` shows `OnboardingFlowView` until `profiles.first?.onboardingCompleted == true`, then `MainTabView`. There is a SECOND gate: in `.onAppear`, if onboarding is done but `!ModuleManager.shared.hasOnboarded`, it presents `ModulePickerView(isOnboarding: true)` full-screen.

**The install state lives in `Platform/SubAppRegistry.swift` (`SubAppRegistry.shared`):**
- `subApps: [any SubApp]` — every registered sub-app: built-in module-backed (`BuiltInModuleSubApp` or migrated conformers like `SleepSubApp`, `TasksSubApp`, …), built-in extras (`ActivitySubApp`, `HealthSubApp`, `JournalSubApp`, `StressSubApp`, `MeditationSubApp`, `SymptomsLabsSubApp`), and spec-driven (`SpecSubApp(spec:)` for `BuiltInSpecs.moodCheckIn` + user-created from `UserSubAppStore`).
- **THE DEFAULT BUG TO FIX:** `var enabledIDs: Set<SubAppID>` getter returns `Set(subApps.map { $0.id })` (i.e. **ALL enabled**) when nothing is persisted. This is what makes every module ship on. The mission flips this default to **empty** for fresh installs, with a migration that grandfathers existing users.
- `isEnabled(_:)`, `setEnabled(_:_:)`, `toggle(_:)`, `setInitial(_:)`, `hasOnboarded` (UserDefaults key `hasCompletedModuleOnboarding`; enabled set under `enabledModules`).
- `registerAllRoutes()` currently registers routes for **all** `subApps` regardless of install state. `loadUserSpecs()` loads user specs.

**Legacy bridge:** `App/AppTheme.swift` → `enum AppModule: CaseIterable` (`name`, `icon`, `color`, `description`) and `class ModuleManager` (delegates storage to `SubAppRegistry`: `enabledModules`, `isEnabled(_:)`, `setInitialModules(_:)`, `runMigrations()`). Also `enum AppRoute` + `destinationView(for:)` (in `Views/RootViews.swift`).

**Install/catalog UI that exists:**
- `Views/ModulePickerView.swift` — grid over `AppModule.allCases`; onboarding mode calls `ModuleManager.shared.setInitialModules(selected)`, manage mode sets `enabledModules`. **It does NOT include spec/registry sub-apps and its copy says "modules you need," not "install."** This is the natural home for the unified install catalog.
- `Views/MySubAppsView.swift` — lists user-created/installed spec sub-apps (enable/disable, edit, uninstall).
- `Views/SubAppRegistryView`-style browse (`AppRoute.subAppRegistry`) backed by `Platform/SubAppRegistryService.swift` (`BundledSubAppRegistryService`, `RegistrySpecs.waterIntake/gratitudeJournal/readingLog`) + `SubAppRegistryStore` (`installedIDs`, `markInstalled/markUninstalled`). NOTE: registry has its OWN `installedIDs` concept separate from `enabledIDs` — these must be reconciled into one install model (registry install should also flip the registry's `enabledIDs`/install state so the sub-app appears).

**Where modules get rendered (every surface that must respect install state):**
- **Tabs:** `MainTabView` in `Views/RootViews.swift` (`enum MainTab`, `tabOrder` in `@AppStorage("tabOrder")`). The five-ish tabs are currently static, not install-driven.
- **Home dashboard:** `Views/HomeView.swift` (`@AppStorage("homeModuleOrder")`, `enum HomeModule`); cards via `SubApp.dashboardCard(context:)`.
- **Sidebar:** `Views/SidebarView.swift`.
- **Coach tools:** `Coach/Tools/ToolRegistry.swift` merges `SubAppRegistry.shared.aiTools(flags:)` — currently from ALL subApps. Must filter to installed only.
- **Routing:** `registerAllRoutes()` + `destinationView(for:)` — should not deep-link into uninstalled modules.
- **Settings:** module rows in `Views/SettingsView.swift`.

**Coach platform tools (so the brain can install/uninstall too):** `Coach/Tools/PlatformControlTools.swift` has `list_modules`, `set_module_enabled`, `save_subapp`, `uninstall_subapp`, `navigate_to`. The confirm-card flow is `Coach/Orchestration/PendingAction.swift` (`Kind`: …`disableModule`, `uninstallSubApp`, `deleteEntity`) + `PendingActionExecutor.swift` + `Coach/Schema/CoachActionCardView.swift`.

**Seeding:** `Persistence/SeedData.swift` (`seedDemo`, `seedExerciseCatalogIfNeeded`, `clearAll`) and `Persistence/ModelContainerFactory.swift` (`coreModels` + `SubAppRegistry.shared.allModels`). Schema includes all models regardless of install (fine — keep schema stable; just don't surface uninstalled modules' UI/seed user-visible demo rows for them).

**Known gaps (the work):** default is "all installed"; onboarding seeds everything and `ModulePickerView` excludes spec/registry sub-apps; tabs/Home/sidebar/routes/Coach-tools render modules without checking install state; built-ins can't truly be uninstalled (they reappear); registry `installedIDs` and registry `enabledIDs` are two parallel notions; no first-run "empty shell + catalog" experience.

---

## 2. Architecture Target (what we are building toward)

### 2.1 One install model on `SubAppRegistry`
A single set, `installedIDs: Set<SubAppID>`, is the source of truth for "this module is present in the app." Provide:
- `isInstalled(_ id:) -> Bool`, `install(_ id:)`, `uninstall(_ id:)`, `installedSubApps: [any SubApp]` (registered AND installed), `setInitialInstalled(_ ids:)`.
- **Default empty.** When nothing is persisted AND the install migration has run, the installed set is `[]`. Keep `enabledIDs` as an internal alias or fold it into `installedIDs` — but the *getter must no longer default to "all"*. (Decide: rename `enabledIDs`→`installedIDs` with a back-compat shim, OR layer `installedIDs` on top and treat enable/disable as a sub-state of installed. Default recommendation: treat install == enable, collapse to one set, keep `ModuleManager` API working via the shim.)
- A `hasChosenInitialModules` flag (reuse `hasOnboarded`) so first-run shows the catalog exactly once; afterward the catalog is reachable from Settings/Modules and the Coach.

### 2.2 First-run "empty shell + install catalog"
- Fresh install → onboarding completes → present the unified **Install Catalog** (evolve `ModulePickerView`) with **zero pre-selected** modules and "Install" language. The catalog lists **all** registered sub-apps (built-in + spec + registry), grouped (e.g. Health, Daily Life, Productivity, Mindfulness, Community, Custom), each a card with name/icon/summary and an Install toggle. Confirm writes `setInitialInstalled(selected)`.
- The shell with zero installed modules is still usable: it shows Home (empty-state inviting "Install modules"), the Coach, and a prominent entry to the catalog. No crashes when nothing is installed.

### 2.3 Every render surface respects install state
- **Tabs:** derive the tab set from installed sub-apps (a sub-app may declare a preferred tab slot) with sensible fixed anchors (Home, Coach, Catalog/Settings). Never show a tab for an uninstalled module.
- **Home:** only show dashboard cards for installed sub-apps; uninstalled ones never appear in `HomeModule` ordering. Empty state when none installed.
- **Sidebar / Settings / module lists:** iterate `installedSubApps`, not `AppModule.allCases`.
- **Routing:** `registerAllRoutes()` registers routes only for installed sub-apps (or guards destinations so a stale deep-link into an uninstalled module shows an "install this module" prompt instead of broken UI). Re-register on install/uninstall.
- **Coach tools:** `ToolRegistry` merges `aiTools` only from installed sub-apps; `list_modules` reports installed + available-to-install; `set_module_enabled` becomes install/uninstall.

### 2.4 Unify built-in + spec + registry installs
- Installing a built-in flips `installedIDs`. Installing a registry/spec sub-app does the package verify/guardrail/permission flow (existing) AND flips `installedIDs` so it appears like any other module. `MySubAppsView` and the registry browse both read/write the same install model. Reconcile `SubAppRegistryStore.installedIDs` so registry-install ⇒ registry sub-app is installed in the one model (keep ratings/version tracking where it lives).

### 2.5 Uninstall = hide, not delete
- Uninstall removes the module from every surface and from `installedIDs`; underlying SwiftData records are **preserved** so reinstalling restores them. Offer a distinct, **confirmed** "Remove module and its data" path (routes through `PendingAction` → `deleteEntity`/a new kind) for users who want a clean wipe. Built-ins are uninstallable just like spec apps.

### 2.6 Teach the brain
- Update `Coach/Context/CoachPromptBuilder.swift` so the model knows modules are installed/uninstalled (not just enabled/disabled), that uninstalled features are absent, and that it can install a module to fulfill a request ("install Sleep so I can track this") via the platform tools — install immediate, uninstall-with-data-wipe confirmed.

---

## 3. Roadmap (ordered; each item is one safe, shippable iteration)

**Phase A — Invert the default + migrate safely (highest leverage)**
- A1. Add the unified install model to `SubAppRegistry`: `installedIDs`, `isInstalled`, `install`, `uninstall`, `installedSubApps`, `setInitialInstalled`. Make the persisted-empty default `[]`. Add a one-time migration: if a user is already onboarded (`hasOnboarded == true` or legacy `enabledModules` data exists), seed `installedIDs` from their current enabled set so they keep their app; brand-new installs start empty. Keep `ModuleManager`/`enabledIDs` working via a shim. Build green; no UI change yet.
- A2. Gate `registerAllRoutes()` to installed sub-apps and re-register on install/uninstall (post a notification or call from install/uninstall). Guard `destinationView(for:)`/sub-app destinations so an uninstalled module routes to an "install" prompt rather than broken UI.

**Phase B — First-run empty shell + unified catalog**
- B1. Evolve `ModulePickerView` into the **Install Catalog**: include built-in + spec + registry sub-apps (read all registered + registry listings), grouped by category, **zero pre-selected** in onboarding, "Install"/"Installed" language, writes `setInitialInstalled`. Reachable later from Settings → Modules and a Home entry.
- B2. Make the zero-installed shell graceful: Home empty state ("Install your first module"), Catalog reachable, Coach available; no crashes when installed set is empty. Wire the first-run presentation to the new flag.

**Phase C — Make every surface install-aware**
- C1. Tabs: derive `MainTabView` tabs from installed sub-apps + fixed anchors; hide tabs for uninstalled modules.
- C2. Home: filter `HomeView` cards/ordering to installed sub-apps only.
- C3. Sidebar + Settings module rows: iterate `installedSubApps`.
- C4. Coach `ToolRegistry`: merge `aiTools` only from installed sub-apps; update `list_modules`/`set_module_enabled` semantics to install/uninstall.

**Phase D — Unify built-in/spec/registry + uninstall semantics**
- D1. Reconcile registry install (`SubAppRegistryStore`) with the one `installedIDs` model so installing from the registry surfaces the sub-app everywhere; `MySubAppsView` reads the same model. Built-ins become uninstallable.
- D2. Uninstall = hide + preserve data; add a separate confirmed "remove data too" path via `PendingAction`. Update `PlatformControlTools` (`set_module_enabled` → install/uninstall) + `CoachPromptBuilder` so the brain can install/uninstall and knows uninstalled features are absent.

**Phase E — Polish + hardening**
- E1. Catalog UX: search, category grouping, "Installed" badges, install/uninstall from detail; design-system compliant; accessibility (Dynamic Type, VoiceOver, 44pt targets).
- E2. Tests: install/uninstall flips state and surfaces; fresh-install default is empty; migration grandfathers existing users; uninstall preserves data; reinstall restores; Coach tools/routes reflect install state.

---

## 4. THE LOOP PROMPT (paste this each session)

```
You are continuing a long-running project: making EVERY PulseLoop module
installable and separate from the app, so that NO module comes standard. A fresh
install starts as a near-empty shell; the user installs the modules they want
(built-in AND spec/registry) from a catalog, and uninstalled modules never clutter
the app (no tab, Home card, sidebar row, route, Coach tool, or settings row). Your
single source of truth is docs/INSTALLABLE_MODULES_LOOP_PROMPT.md (mission §0, code
anchors §1, architecture target §2, roadmap §3, guardrails §5) and the live tracker
docs/INSTALLABLE_PROGRESS.md.

Do EXACTLY ONE iteration, then stop. Follow this loop:

1. ORIENT. Read docs/INSTALLABLE_MODULES_LOOP_PROMPT.md and
   docs/INSTALLABLE_PROGRESS.md. If INSTALLABLE_PROGRESS.md does not exist, create it
   from the §3 roadmap with every item set to "pending", then treat iteration A1 as
   current.

2. SELECT. Pick the single highest-priority "pending" iteration (top-to-bottom in
   §3). Restate it in one sentence. If it is too big for one safe, shippable step,
   split it: do the first sub-step now and add the remainder as new pending items.

3. PLAN. Write a short todo list for this iteration only. Verify the exact real
   files from §1 by reading them — never invent file paths, types, or model fields.
   Confirm the actual SubAppRegistry API, ModuleManager bridge, AppModule cases, and
   the render surfaces (MainTabView, HomeView, SidebarView, ToolRegistry,
   registerAllRoutes) before changing them.

4. IMPLEMENT. Make the change, reusing existing patterns:
   - Route ALL "is this module present?" checks through the install API on
     SubAppRegistry (isInstalled / installedSubApps). Never render from
     AppModule.allCases or the full subApps list ignoring install state.
   - Default for fresh installs is EMPTY (nothing installed). Provide the one-time
     migration that grandfathers already-onboarded users from their current enabled
     set, so upgrades never empty a user's app. Brand-new installs only start empty.
   - Install and uninstall are one tap and reversible. Uninstall HIDES a module and
     PRESERVES its SwiftData data. A separate "remove data too" path is destructive
     and MUST go through the PendingAction confirm-card flow.
   - Built-in, spec-driven, and registry sub-apps all flow through the ONE install
     model. Reconcile SubAppRegistryStore.installedIDs into it; don't leave two
     parallel notions of "installed".
   - Re-register routes and refresh install-aware surfaces on install/uninstall.
   - TEACH THE MODEL: when behavior the brain relies on changes (modules now
     install/uninstall; uninstalled features are absent; it can install a module to
     fulfill a request), update CoachPromptBuilder.systemPrompt and the
     PlatformControlTools descriptions/semantics.
   - Design system is law: PulseColors/PulseFont/PulseRadius, components from
     AppTheme.swift + Components.swift, .cursor/rules/design-system.mdc. SF Symbols
     only, no emoji in UI, primary buttons black, hairline cards, calm whitespace.
   - SwiftData changes are additive/lightweight only; never drop user data.

5. VERIFY. Build and resolve errors before finishing:
   xcodebuild -project PulseLoop.xcodeproj -scheme PulseLoop \
     -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
   Run ReadLints on edited files. Where §3 calls for it, add/adjust tests (use the
   in-memory ModelContainerFactory.make(inMemory:true) + UserDefaults isolation
   patterns already in PulseLoopTests). Sanity-check the zero-installed shell does
   not crash. The app MUST build at the end of the iteration.

6. RECORD. Update docs/INSTALLABLE_PROGRESS.md: mark this iteration done with a 1–3
   line summary (what changed + which files + any new API/flags), list follow-ups you
   spun off, and clearly name the NEXT pending iteration.

7. STOP. Post a concise summary: what you did, build status, the next iteration. Do
   not start the next iteration. Do not create a git commit unless I ask.

Rules of engagement:
- Keep the build green; never leave a broken state.
- The fresh-install default is EMPTY; existing users are grandfathered by migration.
- One install model on SubAppRegistry is the single source of truth; every surface
  (tabs, Home, sidebar, settings, routes, Coach tools) reads it.
- Uninstall hides + preserves data; wiping data is a separate confirmed action.
- Built-in modules are as uninstallable as spec/registry ones.
- Prefer small, reversible, additive steps so old paths keep working mid-migration.
- If a decision has real product trade-offs (collapse enabled into installed vs.
  layer them; how tabs derive from installed apps; category grouping), state your
  default, proceed, and note it in the tracker rather than blocking.
- If you find the roadmap is wrong, propose the fix in the tracker and adjust, but
  still complete one concrete shippable step this iteration.
```

---

## 5. Guardrails (referenced by the loop — the hard rules)

- **Build green every iteration.** End state compiles and runs; Xcode build + ReadLints are the gate. The zero-installed shell must not crash.
- **No module comes standard.** Fresh installs start with an empty installed set. Built-in, spec, and registry modules are all opt-in through one install model.
- **Grandfather existing users.** A one-time migration seeds `installedIDs` from an already-onboarded user's current enabled set so upgrading never empties their app. Only genuinely fresh installs are empty.
- **One source of truth.** Every "is this module present?" decision reads `SubAppRegistry` install state. Eliminate rendering that iterates all modules ignoring install state. Reconcile the registry's separate `installedIDs` into the one model.
- **Uninstall preserves data.** Uninstalling hides a module everywhere and keeps its SwiftData records for a later reinstall. Removing data is a distinct, explicit action that goes through the `PendingAction` confirm card. Never silently delete user data on uninstall.
- **Reversible & additive.** Install/uninstall are one tap and reversible. SwiftData migrations are additive/lightweight with tolerant decoders; the schema may keep all models, but uninstalled modules surface no UI/seeded demo rows.
- **Teach the brain.** When module semantics change (install/uninstall, absent features, install-to-fulfill), update `CoachPromptBuilder.systemPrompt` and `PlatformControlTools`. An untaught capability is wasted.
- **Design system is law.** `PulseColors`/`PulseFont`/`PulseRadius`/`PulseLayout` + components from `App/AppTheme.swift` + `DesignSystem/Components.swift`; obey `.cursor/rules/design-system.mdc`. SF Symbols only (no emoji in rendered UI). Primary buttons black, accent sparingly, hairline-bordered cards, calm whitespace.
- **Accessibility & quality.** Dynamic Type, VoiceOver labels, 44pt tap targets on every new surface (catalog cards, install buttons, empty states).
- **One iteration at a time.** A single shippable step, then stop — keeping the project reviewable.
