# PulseLoop → Modular Sub-App Platform — Progress Tracker

> Live status for the modularization effort. Source of truth for the roadmap is
> `docs/LOOP_PROMPT.md` (mission §0, anchors §1, target §2, roadmap §3, guardrails §5).
> Each loop iteration updates this file: mark the iteration done, summarize the
> change + touched files, list follow-ups, and name the next pending iteration.

**Status legend:** `pending` · `in-progress` · `done` · `blocked`

**Current iteration:** — (roadmap complete; post-roadmap work ongoing)
**Last completed:** H1 — AWS Bedrock (Claude) coach provider
**Build status at last iteration end:** ✅ `BUILD SUCCEEDED` (iOS Simulator, scheme `PulseLoop`).

---

## Phase A — Foundations & Safety

| ID | Iteration | Status |
|----|-----------|--------|
| A1 | Create `docs/MODULAR_PROGRESS.md` tracker; remove/secure the hard-coded key in `Services/AIService.swift` (move to Keychain/config, fail gracefully). | done |
| A2 | Define the `SubApp` protocol + `SubAppRegistry` scaffolding (no behavior change yet; `ModuleManager` delegates to it). | done |
| A3 | Make routing pluggable: introduce a router that accepts route contributions from sub-apps; keep `AppRoute` working via an adapter. | done |
| A4 | Make the schema pluggable: `ModelContainerFactory` assembles its `Schema` from `SubAppRegistry.allModels` + core models. | done |
| A5 | Make `ToolRegistry` accept tool contributions from sub-apps. | done |

## Phase B — Migrate built-in sub-apps (one per iteration)

| ID | Iteration | Status |
|----|-----------|--------|
| B1 | Migrate **Sleep** to a `SubApp` conformer + one UX upgrade. | done |
| B2 | Migrate **Activity** (+ Record/GPS) + one UX upgrade. | done |
| B3 | Migrate **Health/Vitals** + one UX upgrade. | done |
| B4 | Migrate **Fitness** (strength) + one UX upgrade. | done |
| B5 | Migrate **Protocol/Supplements** + one UX upgrade. | done |
| B6 | Migrate **Nutrition** (meals) + one UX upgrade. | done |
| B7 | Migrate **Tasks** (+ WeekPlanner) + one UX upgrade. | done |
| B8 | Migrate **Notes** + one UX upgrade. | done |
| B9 | Migrate **Journal** + one UX upgrade. | done |
| B10 | Migrate **Mood** + one UX upgrade. | done |
| B11 | Migrate **Stress** + one UX upgrade. | done |
| B12 | Migrate **Meditation** + one UX upgrade. | done |
| B13 | Migrate **Symptoms/Labs** + one UX upgrade. | done |
| B14 | Migrate **Quit Program** + one UX upgrade. | done |
| B15 | Migrate **Friends/Accountability** + one UX upgrade. | done |
| B16 | Migrate **Inbox/AI Capture** + one UX upgrade. | done |
| B17 | Migrate **Day Plan** + one UX upgrade. | done |

## Phase C — Declarative runtime

| ID | Iteration | Status |
|----|-----------|--------|
| C1 | `SubAppSpec` Codable schema + strict validator + versioning. | done |
| C2 | `SubAppRuntime` renders list/detail/form/dashboard from a spec (design-system widgets only). | done |
| C3 | Spec-driven persistence (dynamic entities) + additive migration. | done |
| C4 | Re-express ONE simple built-in (e.g. Mood) as a spec to prove the runtime. | done |

## Phase D — AI Sub-App Builder

| ID | Iteration | Status |
|----|-----------|--------|
| D1 | Coach tool(s) `generate_subapp_spec` / `refine_subapp_spec` (strict JSON schema). | done |
| D2 | Builder UI: describe → preview → refine → save as `.userCreated` SubApp. | done |
| D3 | Guardrails: validation, permission prompts, design-system conformance, safety review. | done |

## Phase E — Credits & Billing

| ID | Iteration | Status |
|----|-----------|--------|
| E1 | `CreditsLedger` + metering hooks on every AI call. | done |
| E2 | Paywall + StoreKit 2 credit-pack purchases + balance UI. | done |
| E3 | Enforcement seam via `backendProxy` provider mode. | done |

## Phase F — Sharing / Registry

| ID | Iteration | Status |
|----|-----------|--------|
| F1 | Export/import signed `SubAppSpec`. | done |
| F2 | Registry browse/install/rate; install flow with permission review. | done |
| F3 | Moderation/safety + versioned updates for installed sub-apps. | done |

## Phase G — Enterprise hardening

| ID | Iteration | Status |
|----|-----------|--------|
| G1 | Per-sub-app analytics, error recovery, accessibility audit, tests. | done |

## Phase H — Post-roadmap (provider expansion)

| ID | Iteration | Status |
|----|-----------|--------|
| H1 | AWS Bedrock (Claude) coach provider — BYO IAM credentials, SigV4, OpenAI↔Anthropic translation. | done |

---

## Iteration Log

### A1 — Tracker + secure legacy AI key (done)

**What changed**
- Created this tracker (`docs/MODULAR_PROGRESS.md`) from the §3 roadmap.
- Removed the hard-coded plaintext OpenRouter key from `Services/AIService.swift`.
  The key is now resolved at runtime via a new `OpenRouterKeychainStore`
  (reusing the existing `APIKeyStore` protocol from
  `Coach/Config/OpenAIKeychainStore.swift`), with a transitional fallback to a
  build-time value supplied through `OPENROUTER_API_KEY` (env var or
  `Info.plist`). When no key is available, AI calls **fail gracefully** with a
  new `AIError.missingAPIKey` instead of sending a request with an empty/leaked
  credential.

**Files touched**
- `docs/MODULAR_PROGRESS.md` (new)
- `PulseLoop/Coach/Config/OpenAIKeychainStore.swift` (added `OpenRouterKeychainStore`)
- `PulseLoop/Services/AIService.swift` (key resolution + `AIError.missingAPIKey`)

**Follow-ups spun off**
- The legacy `AIService` should ultimately be retired in favor of the Coach
  orchestrator (see LOOP_PROMPT §1 "AI consolidation"). Until then, a Settings
  affordance to enter the OpenRouter key (mirroring the Coach key entry) would
  let users supply their own key. Tracked informally; not yet a roadmap item.

**Next iteration:** A2 — Define the `SubApp` protocol + `SubAppRegistry`
scaffolding (no behavior change yet; `ModuleManager` delegates to it).

### A2 — SubApp protocol + SubAppRegistry scaffolding (done)

**What changed**
- Added `PulseLoop/Platform/SubApp.swift`: the `SubApp` protocol plus supporting
  types (`SubAppID`, `SubAppOrigin`, `SubAppPermission`) with safe defaults so
  features can adopt incrementally.
- Added `PulseLoop/Platform/SubAppRegistry.swift`: a registry holding the built-in
  sub-apps (one `BuiltInModuleSubApp` per `AppModule`), exposing `allModels`
  (seam for A4) and owning enable/disable + onboarding state via the **same**
  UserDefaults keys the legacy `ModuleManager` used.
- Refactored `ModuleManager` (`App/AppTheme.swift`) to delegate all storage to
  `SubAppRegistry` while keeping its `AppModule`-based API. No behavior change;
  saved module selections migrate transparently.

**Files touched**
- `PulseLoop/Platform/SubApp.swift` (new)
- `PulseLoop/Platform/SubAppRegistry.swift` (new)
- `PulseLoop/App/AppTheme.swift` (`ModuleManager` delegates to registry)

**Next iteration:** A3 — Make routing pluggable: a router that accepts route
contributions from sub-apps; keep `AppRoute` working via an adapter.

### A3 — Pluggable routing seam (done)

**What changed**
- Added `PulseLoop/Platform/SubAppRouter.swift`: a `SubAppRouter` (+ `SubAppRoute`
  marker protocol, `RouteContext` carrying the `NavigationPath` binding). Sub-apps
  register a destination type + builder; a `.subAppNavigationDestinations(path:)`
  view modifier installs one `.navigationDestination` per registered type.
- Extended `SubApp` with a `registerRoutes(with:)` hook (default no-op) and added
  `SubAppRegistry.registerAllRoutes()`.
- Wired both into `RootAppView`: the existing `AppRoute` switch is untouched (still
  the source of truth for all current screens); the router is installed alongside
  it and `registerAllRoutes()` runs at startup. Old + new paths coexist.

**Files touched**
- `PulseLoop/Platform/SubAppRouter.swift` (new)
- `PulseLoop/Platform/SubApp.swift` (`registerRoutes` hook)
- `PulseLoop/Platform/SubAppRegistry.swift` (`registerAllRoutes()`)
- `PulseLoop/Views/RootViews.swift` (install router + call at startup)

**Next iteration:** A4 — Make the schema pluggable: `ModelContainerFactory`
assembles its `Schema` from `SubAppRegistry.allModels` + core models.

### A4 — Pluggable schema assembly (done)

**What changed**
- Refactored `Persistence/ModelContainerFactory.swift`: the ~55-model list is now
  `coreModels`; `allModels` = `coreModels` + `SubAppRegistry.shared.allModels`,
  de-duplicated by metatype (`ObjectIdentifier`). `make(inMemory:)` builds the
  `Schema` from `allModels`. Behavior-preserving (built-ins contribute no models
  yet) but features can now ship their own models via the `SubApp` protocol.

**Files touched**
- `PulseLoop/Persistence/ModelContainerFactory.swift`

### A5 — ToolRegistry accepts sub-app tools (done)

**What changed**
- Extended `SubApp` with `aiTools(flags:) -> [AnyCoachTool]` (default none) and
  added `SubAppRegistry.aiTools(flags:)` to gather them.
- `Coach/Tools/ToolRegistry.swift` now merges sub-app-contributed tools into its
  tool map (core tools win on name collision; merge avoids the previous
  `uniqueKeysWithValues` crash risk). Built-ins contribute none yet — this is the
  seam Phase B features use.

**Files touched**
- `PulseLoop/Platform/SubApp.swift` (`aiTools` hook)
- `PulseLoop/Platform/SubAppRegistry.swift` (`aiTools(flags:)`)
- `PulseLoop/Coach/Tools/ToolRegistry.swift` (merge sub-app tools)

**Phase A complete.** The three centralization points (routing, schema, tools)
plus enable/disable state now all have pluggable seams that built-in features and
future user/installed sub-apps feed into, with old paths fully intact.

**Next iteration:** B1 — Migrate **Sleep** to a `SubApp` conformer + one UX upgrade.

### B1 — Sleep SubApp + UX upgrade (done)

**What changed**
- Added `dashboardCard(context:)` to the `SubApp` protocol (default nil) and made
  `registerRoutes` `@MainActor`.
- Added `PulseLoop/Platform/SubApps/SleepSubApp.swift`: first real `SubApp`
  conformer. Owns `SleepSession`/`SleepStageBlock`/`SleepLog` models, registers a
  `SleepRoute.dashboard` destination (→ `SleepView`) via the router, declares
  `.healthRead` permission, and provides a Home dashboard card (`SleepDashboardCard`)
  summarizing last night's duration + score. Legacy `AppRoute.sleep` still works.
- Registered `SleepSubApp` in `SubAppRegistry` (substitutes the generic
  `BuiltInModuleSubApp` for `.sleep`).
- **UX upgrade:** `SleepView` aggregate view now shows a guiding empty state
  ("Not enough nights yet…") instead of an empty histogram when <2 nights tracked.

**Files touched**
- `PulseLoop/Platform/SubApp.swift` (`dashboardCard`, `@MainActor registerRoutes`)
- `PulseLoop/Platform/SubApps/SleepSubApp.swift` (new)
- `PulseLoop/Platform/SubAppRegistry.swift` (register conformer)
- `PulseLoop/Views/SleepView.swift` (aggregate empty state)

**Follow-up:** the `SleepDashboardCard` is defined but not yet rendered on Home
(HomeView has its own sleep button). A later iteration should switch Home to render
sub-app dashboard cards from the registry. Tracked here.

**Next iteration:** B2 — Migrate **Activity** (+ Record/GPS) + one UX upgrade.

### B2 — Activity SubApp + UX upgrade (done)

**What changed**
- Added `PulseLoop/Platform/SubApps/ActivitySubApp.swift`: owns the cardio models
  (`ActivitySession`, `ActivitySample`, `ActivityGpsPoint`, `ActivityEvent`,
  `ActivitySensorPollEvent`, `ActivityDaily`) and registers `ActivityRoute`
  (dashboard / recordSelect / recordLive / recordSummary / detail) through the
  router using `RouteContext.path`. Carries its own `SubAppID("activity")` since
  Activity isn't backed by a legacy `AppModule`.
- `SubAppRegistry` now appends non-module-backed "extra" built-in sub-apps.
- **UX upgrade:** the "+ Record Activity" primary button in `ActivityView` now uses
  `Color.black` (design-system rule: primary buttons are black, not accent).

**Files touched**
- `PulseLoop/Platform/SubApps/ActivitySubApp.swift` (new)
- `PulseLoop/Platform/SubAppRegistry.swift` (extras list)
- `PulseLoop/Views/ActivityView.swift` (black primary button)

**Next iteration:** B3 — Migrate **Health/Vitals** + one UX upgrade.

### B3 — Health SubApp + UX upgrade (done)

**What changed**
- Added `PulseLoop/Platform/SubApps/HealthSubApp.swift`: owns ring/device +
  measurement models (`Device`, `Measurement`, `DerivedUpdateRow`, `RawPacketRow`)
  and registers `HealthRoute` (dashboard / vitals). Own `SubAppID("health")`.
  Registered in the `SubAppRegistry` extras.
- **UX upgrade:** the HR and SpO₂ cards in `VitalsView` now expose combined
  VoiceOver labels + values so the metric reads as a single coherent element.

**Files touched**
- `PulseLoop/Platform/SubApps/HealthSubApp.swift` (new)
- `PulseLoop/Platform/SubAppRegistry.swift` (extras)
- `PulseLoop/Views/VitalsView.swift` (accessibility)

**Next iteration:** B4 — Migrate **Fitness** (strength) + one UX upgrade.

### B4 — Fitness SubApp + UX upgrade (done)
- Added `SubApps/FitnessSubApp.swift` (backed by `AppModule.workouts`): owns
  `Exercise`/`WorkoutTemplate`/`TemplateExercise`/`ExerciseSet`/`WorkoutLog`/
  `BodyMetric`; registers `FitnessRoute` (dashboard/builder/library). Substituted in
  the registry `migrated` map.
- **UX upgrade:** Fitness empty-state "New Workout" button now black (design rule).
- Files: `SubApps/FitnessSubApp.swift` (new), `SubAppRegistry.swift`,
  `Views/FitnessDashboardView.swift`.

**Next iteration:** B5 — Migrate **Protocol/Supplements** + one UX upgrade.

### B5 — Protocol SubApp + UX upgrade (done)
- Added `SubApps/ProtocolSubApp.swift` (backed by `AppModule.protocol_`): owns
  `Medication`/`MedicationLog`/`Routine`/`RoutineStep`. No routes (protocol UI lives
  in `TrackerView`). Registered in registry.
- **UX upgrade:** "Log dose now" primary button in `ProtocolDetailView` now black
  (design rule); success-green retained for the logged state.
- Files: `SubApps/ProtocolSubApp.swift` (new), `SubAppRegistry.swift`,
  `Views/ProtocolDetailView.swift`.

**Next iteration:** B6 — Migrate **Nutrition** (meals) + one UX upgrade.

### B6 — Nutrition SubApp + UX upgrade (done)
- Added `SubApps/NutritionSubApp.swift` (backed by `AppModule.nutrition`): owns
  `MealLog`. Registered in registry.
- **UX upgrade:** the nutrition calorie/macro ring in `TrackerView` now has a
  combined VoiceOver label + value summarizing calories and macros.
- Files: `SubApps/NutritionSubApp.swift` (new), `SubAppRegistry.swift`,
  `Views/TrackerView.swift`.

**Next iteration:** B7 — Migrate **Tasks** (+ WeekPlanner) + one UX upgrade.

### B7 — Tasks SubApp + UX upgrade (done)
- Added `SubApps/TasksSubApp.swift` (backed by `AppModule.tasks`): owns
  `TaskItem`/`TaskBoard`; registers `TasksRoute.list` (→ `TasksView`). Registered.
- **UX upgrade:** "Add" task primary button in `TasksView` now black (design rule).
- Files: `SubApps/TasksSubApp.swift` (new), `SubAppRegistry.swift`,
  `Views/TasksView.swift`.

**Next iteration:** B8 — Migrate **Notes** + one UX upgrade.

### B8 — Notes SubApp + UX upgrade (done)
- Added `SubApps/NotesSubApp.swift` (backed by `AppModule.notes`): owns
  `Note`/`NoteBlock`/`Collection`; registers `NotesRoute` (list/editor). Registered.
- **UX upgrade:** new-note "+" primary button in `NotesListView` now black.
- Files: `SubApps/NotesSubApp.swift` (new), `SubAppRegistry.swift`,
  `Views/NoteEditorView.swift`.

**Next iteration:** B9 — Migrate **Journal** + one UX upgrade.

### B9 — Journal SubApp + UX upgrade (done)
- Added `SubApps/JournalSubApp.swift` (own `SubAppID("journal")`): owns
  `JournalDay`/`JournalMetricEntry`; registers `JournalRoute.dashboard`. Added to
  registry extras.
- **UX upgrade:** the "Copy entries from yesterday" button in `JournalView` is now
  hidden when there are no copyable yesterday entries (was a silent no-op), and
  gained a VoiceOver hint.
- Files: `SubApps/JournalSubApp.swift` (new), `SubAppRegistry.swift`,
  `Views/JournalView.swift`.

**Next iteration:** B10 — Migrate **Mood** + one UX upgrade.

### B10 — Mood SubApp + UX upgrade (done)
- Added `SubApps/MoodSubApp.swift` (backed by `AppModule.moodTracking`): owns
  `MoodEntry`. Registered.
- **UX upgrade:** "Save Check-in" primary button in the mood sheet now black.
- Files: `SubApps/MoodSubApp.swift` (new), `SubAppRegistry.swift`,
  `Views/WellnessTrackingViews.swift`.

**Next iteration:** B11 — Migrate **Stress** + one UX upgrade.

### B11 — Stress SubApp + UX upgrade (done)
- Added `SubApps/StressSubApp.swift` (own `SubAppID("stress")`): owns `StressLog`.
  Registered in extras.
- **UX upgrade:** "Log Stress" primary button now black.
- Files: `SubApps/StressSubApp.swift` (new), `SubAppRegistry.swift`,
  `Views/StressMeditationFinanceViews.swift`.

**Next iteration:** B12 — Migrate **Meditation** + one UX upgrade.

### B12 — Meditation SubApp + UX upgrade (done)
- Added `SubApps/MeditationSubApp.swift` (own `SubAppID("meditation")`): owns
  `MeditationLog`. Registered in extras.
- **UX upgrade:** "Log Session" primary button now black.
- Files: `SubApps/MeditationSubApp.swift` (new), `SubAppRegistry.swift`,
  `Views/StressMeditationFinanceViews.swift`.

**Next iteration:** B13 — Migrate **Symptoms/Labs** + one UX upgrade.

### B13 — Symptoms/Labs SubApp + UX upgrade (done)
- Added `SubApps/SymptomsLabsSubApp.swift` (own `SubAppID("symptoms_labs")`): owns
  `SymptomLog`/`LabResult`. Registered in extras.
- **UX upgrade:** "Log Symptom" + "Save Result" primary buttons now black.
- Files: `SubApps/SymptomsLabsSubApp.swift` (new), `SubAppRegistry.swift`,
  `Views/SymptomLabViews.swift`.

**Next iteration:** B14 — Migrate **Quit Program** + one UX upgrade.

### B14 — Quit Program SubApp + UX upgrade (done)
- Added `SubApps/QuitProgramSubApp.swift` (backed by `AppModule.quitProgram`): owns
  `Vice`/`ViceLog`. Registered.
- **UX upgrade:** the icon-only "Log urge" toolbar button now has a VoiceOver label.
- Files: `SubApps/QuitProgramSubApp.swift` (new), `SubAppRegistry.swift`,
  `Views/QuitProgramView.swift`.

**Next iteration:** B15 — Migrate **Friends/Accountability** + one UX upgrade.

### B15 — Friends/Accountability SubApp + UX upgrade (done)
- Added `SubApps/FriendsSubApp.swift` (backed by `AppModule.accountability`): owns
  `Friend`/`FriendActivity`/`Wishlist`/`WishlistItem`/`FriendEvent`/`TravelPlan` and
  registers router-native `FriendsRoute.friends`/`.profile`. Registered.
- **UX upgrade:** the section "Add" button is now black (primary-button design rule)
  instead of accent-tinted.
- Files: `SubApps/FriendsSubApp.swift` (new), `SubAppRegistry.swift`,
  `Views/FriendsView.swift`.

**Next iteration:** B16 — Migrate **Inbox/AI Capture** + one UX upgrade.

### B16 — Inbox/AI Capture SubApp + UX upgrade (done)
- Added `SubApps/InboxSubApp.swift` (backed by `AppModule.aiCapture`): owns
  `InboxItem` and registers router-native `InboxRoute.inbox`/`.mailReply`. Registered.
- **UX upgrade:** the icon-only "mark handled" checkmark button on each inbox row now
  has a VoiceOver label.
- Files: `SubApps/InboxSubApp.swift` (new), `SubAppRegistry.swift`,
  `Views/InboxView.swift`.

**Next iteration:** B17 — Migrate **Day Plan** + one UX upgrade.

### B17 — Day Plan SubApp + UX upgrade (done)
- Added `SubApps/DayPlanSubApp.swift` (backed by `AppModule.dayPlan`): owns
  `DayPlan`/`DayPlanAction` and registers router-native `DayPlanRoute.plan`. Registered.
- **UX upgrade:** the icon-only approve (✓) and skip (✕) buttons on each AI suggestion
  row now have VoiceOver labels ("Approve suggestion" / "Skip suggestion").
- Files: `SubApps/DayPlanSubApp.swift` (new), `SubAppRegistry.swift`,
  `Views/DayPlanView.swift`.

**Phase B complete.** Every built-in feature now has a concrete `SubApp` conformer
owning its models + routes. Next: Phase C (spec-driven runtime).

**Next iteration:** C1 — `SubAppSpec` Codable schema + strict validator + versioning.

### C1 — SubAppSpec schema + validator + versioning (done)
- Added `Platform/SubAppSpec.swift`:
  - `SemanticVersion` value type (string-coded, comparable) + `SubAppSpecSchema.current`.
  - `SubAppSpec` (id/name/icon/summary/author/version/permissions/entities/screens),
    `EntitySpec`, `FieldSpec` (+ `FieldType`), `ScreenSpec` (+ `ScreenKind`).
  - All optional-with-default fields decode tolerantly (`decodeIfPresent`) so partial
    AI output still parses, then gets caught by the validator.
  - `SubAppSpecValidator`: strict checks for schema-major compatibility, slug-only
    identifiers, no-emoji SF Symbol icons, unique entity/field/screen names, and
    referential integrity (list/form/detail screens must point at a declared entity).
    `validate(_:)` throws on any error; `decodeAndValidate(_:)` does both from JSON.
- Additive only — nothing renders/persists from a spec yet (C2/C3).

**Next iteration:** C2 — `SubAppRuntime` renders list/detail/form/dashboard from a
spec (design-system widgets only).

### C2 — SubAppRuntime renders specs (done)
- Added `Platform/SubAppRuntime.swift`:
  - `SubAppFieldValue` (typed dynamic value) + `SubAppRecord` (one entity record).
  - `SubAppRecordStore` protocol (storage seam) + `InMemorySubAppRecordStore`
    (C2 impl; C3 swaps in SwiftData behind the same protocol).
  - `SubAppRuntimeView` + `SubAppScreenView` dispatcher and four screen renderers:
    `list` (PulseCard rows, add via toolbar), `form` (typed field editors —
    text/number/integer/boolean/date/rating-stars/selection-menu — black Save),
    `detail` (read-only field cards), `dashboard` (per-entity record counts).
  - Renders ONLY design-system widgets (`PulseCard`, `InlineEmptyState`,
    `pulseCardSurface`, `PulseFont`, `PulseColors`, black primary buttons).
- Self-contained: not yet wired into navigation/registry (C4 proves it end-to-end).

**Next iteration:** C3 — spec-driven persistence (dynamic entities) + additive
migration.

### C3 — spec-driven persistence + additive migration (done)
- Added `Platform/SubAppPersistence.swift`:
  - `DynamicSubAppRecord` — a single generic `@Model` table keyed by
    `subAppID`+`entity` with a JSON `payload` of field values. One table serves all
    dynamic sub-apps/entities, so adding sub-apps adds zero new SwiftData tables.
  - `CodableFieldValue` — JSON mirror of `SubAppFieldValue` for the payload.
  - `SwiftDataSubAppRecordStore` — production `SubAppRecordStore` (fetch/upsert/delete
    against the generic table). Drop-in for the in-memory store (same protocol).
- Registered `DynamicSubAppRecord.self` in `ModelContainerFactory.coreModels`
  (purely additive — existing per-feature models untouched).
- Refactored `SubAppRuntime` to depend on `any SubAppRecordStore` (not the concrete
  in-memory class) with a `reloadToken` refresh, so it renders identically on either
  backend.

**Next iteration:** C4 — re-express ONE simple built-in (Mood) as a spec to prove
the runtime end-to-end.

### C4 — Mood as a spec proves the runtime (done)
- Added `Platform/SpecSubApp.swift`:
  - `SpecSubApp` — a `SubApp` conformer wrapping a `SubAppSpec` (contributes no
    bespoke models; data lives in the shared `DynamicSubAppRecord` table). This is
    the bridge user-created (D2) and installed (F2) sub-apps will all use.
  - `SpecSubAppRoute` + `SpecSubAppHost` — a router destination that resolves the
    spec by id and binds it to a `SwiftDataSubAppRecordStore` from the environment.
  - `SpecSubAppCatalog` (MainActor lookup) + `BuiltInSpecs` (nonisolated holder) with
    the built-in **Mood Journal** spec: a `checkin` entity (rating + selection + note
    + date) and list/form/detail/dashboard screens.
- Registered the spec sub-app in `SubAppRegistry` extras and added a
  "Mood Journal (spec runtime)" entry in Settings → Tools to reach it. Creating /
  listing / viewing check-ins now works fully through the generic runtime + SwiftData
  store — proving the whole spec → runtime → persistence path.

**Phase C complete.** A declarative spec can now define data + screens and run as a
real, persistent sub-app with no bespoke Swift. Next: Phase D (AI builds the specs).

**Next iteration:** D1 — Coach tool(s) `generate_subapp_spec` / `refine_subapp_spec`
(strict JSON schema).

### D1 — Sub-app builder coach tools (done)
- Added `Coach/Tools/SubAppBuilderTools.swift`:
  - `generate_subapp_spec` + `refine_subapp_spec` — strict-JSON-schema tools mirroring
    `SubAppSpec` (entities → fields w/ type+options, screens w/ kind+entity). Shared
    `guidance` string teaches the slug/SF-Symbol/entity-reference rules.
  - Handler decodes args → `SubAppSpec`, runs `SubAppSpecValidator.issues`, rejects on
    any error (returns the messages), and on success stages the draft + returns
    warnings + a summary.
  - `SubAppBuilderDraftStore` (observable) holds the single in-progress draft for the
    Builder UI (D2).
- Gated behind a new `enableSubAppBuilder` coach setting / `subAppBuilderEnabled`
  flag; `ToolRegistry` adds the tools only when enabled.

**Next iteration:** D2 — Builder UI: describe → preview → refine → save as
`.userCreated` SubApp.

### D2 — Sub-App Builder UI (done)
- Added `Views/SubAppBuilderView.swift` (`AppRoute.subAppBuilder`): describe → the
  coach runs the D1 tools → preview the staged draft (entities/fields/permissions +
  a live `SubAppRuntimeView` preview on an in-memory store) → refine with more
  prompts → **Save sub-app**.
- Added persistence in `SubAppBuilderTools.swift`: `UserSubAppStore` (JSON in
  UserDefaults) for `.userCreated` specs. `SubAppRegistry.loadUserSpecs()` rehydrates
  them into the catalog + registry at startup and after a save.
- Saving validates strictly, persists, re-registers, and confirms. New sub-apps
  reuse the existing `SpecSubAppRoute` so no new wiring is needed.
- Added an `enableSubAppBuilder` toggle to the Coach settings section and a
  "Sub-App Builder" entry under Settings → Tools.

**Next iteration:** D3 — guardrails: validation, permission prompts, design-system
conformance, safety review.

### D3 — Builder guardrails (done)
- Added `Platform/SubAppGuardrails.swift` — policy layer atop the structural
  validator:
  - **Size limits** (≤4 entities, ≤8 fields/entity, ≤6 screens, ≤12 selection
    options) keep generated apps small + on-brand.
  - **Reserved-id protection**: user/installed specs can't shadow a built-in
    sub-app id (AppModule cases, extras, built-in demo specs).
  - **Content safety**: blocks medical/diagnostic/claim language in user-facing text
    (wellness app, not a medical device).
  - Derives the **permission list to review** + human-readable explanations.
- Wired into both seams: the D1 tool handler rejects guardrail-violating specs (and
  reports permissions/warnings to the coach); the Builder save flow runs guardrails
  and shows an explicit **permission-review sheet** before persisting any sub-app
  that requests capabilities.

**Phase D complete.** Users can now describe a tracker, have the AI design + refine a
validated/guard-railed sub-app, preview it live, review its permissions, and save it
as a real persistent sub-app. Next: Phase E (AI credits & billing).

**Next iteration:** E1 — `CreditsLedger` + metering hooks on every AI call.

### E1 — CreditsLedger + metering hooks (done)
- Added `Services/CreditsLedger.swift`: observable, UserDefaults-backed credit
  balance + immutable ledger entries. `AIUsageKind` (coachTurn/summary/notification/
  dailyLearning/subAppGeneration/imageAnalysis) drives a flat `baseCost`. New installs
  get an `initialGrant` of 50 credits. `meter(_:usage:)` records a debit (with token
  usage when available); `grant(_:)` adds credits; `canAfford(_:)` for E2 enforcement.
- Parsed token `usage` from the Responses API into `OpenAIResponse.TokenUsage`, and
  accumulated it across rounds in `CoachOrchestrator.TurnResult` (+ `usedLLM`).
- Metering hook: `CoachViewModel.send` meters each LLM-backed turn (scripted
  fallbacks are free), classifying builder turns as `.subAppGeneration`.

**Next iteration:** E2 — Paywall + StoreKit 2 credit-pack purchases + balance UI.

### E2 — Paywall + StoreKit 2 + balance UI (done)
- Added `Services/CreditStore.swift`: StoreKit 2 wrapper. Loads consumable credit
  packs (`CreditPack`) for known product ids (100/500/2000 credits), runs
  `product.purchase()`, verifies the transaction, grants credits to `CreditsLedger`,
  and finishes the transaction. A `Transaction.updates` listener grants credits for
  Ask-to-Buy/restored purchases too. Degrades gracefully when no products are
  configured (empty pack list, no crash).
- Added `Views/CreditsView.swift` (`AppRoute.credits`): balance card, purchasable
  packs (with loading/purchasing states), and a recent-usage history list — all from
  design-system components.
- Wired `AppRoute.credits` into `RootViews` and added an "AI Credits" entry under
  Settings → Tools.

**Next iteration:** E3 — Enforcement seam via `backendProxy` provider mode.

### E3 — backend-proxy enforcement seam (done)
- Added `Coach/OpenAI/BackendProxyResponsesClient.swift`: a `ResponsesClient` that
  POSTs the verbatim Responses body to `{baseURL}/v1/coach/responses` with a session
  bearer token. The server holds the OpenAI key and is the authoritative credit
  ledger. Handles `402 Payment Required` (→ `ResponsesError.insufficientCredits`) and
  adopts a server-reported `pulseloop_credits.balance` via
  `CreditsLedger.syncAuthoritativeBalance(_:)`.
- `CoachProviderMode.backendProxy` is now live: `CoachFeatureFlags.coachEnabled`
  returns true when a valid `backendProxyURL` is set (no longer a hard `false`), and
  the status line reflects it. Added `backendProxyURL` to `CoachSettings` (tolerant
  decode) + a URL field in the Coach settings section (shown only in proxy mode).
- `CoachViewModel` now (a) **enforces credits up front** — refuses an LLM turn and
  posts a "you're out of credits" assistant message when `canAfford(.coachTurn)` is
  false (server still enforces authoritatively in proxy mode), and (b) selects the
  transport per provider mode via `makeClient(...)`.

**Phase E complete.** AI usage is metered, purchasable, balance-visible, and now
enforced — locally for BYO-key and server-authoritatively through the proxy seam.

**Next iteration:** F1 — Export/import signed `SubAppSpec`.

### F1 — Export/import signed SubAppSpec (done)
- Added `Platform/SubAppPackage.swift`: a `SubAppPackage` envelope (format/algorithm/
  signedAt/spec/signature) + `SubAppPackager`. Export wraps a validated spec and signs
  its **canonical JSON** (sorted keys, fixed options) with HMAC-SHA256; import decodes,
  rejects unsupported formats/algorithms, verifies the signature (tamper-evidence),
  then strictly validates the spec. The shared-key HMAC is the v1 seam; F2/F3 swap in
  server-side asymmetric signing without changing the call sites.
- Added `Views/MySubAppsView.swift` (`AppRoute.mySubApps`): lists `.userCreated`
  sub-apps with **Export** (writes a `.pulseapp` file → share sheet) and **Delete**,
  plus **Import a sub-app** (file importer → verify + guardrail-review → an install
  confirmation sheet showing author + requested permissions). Reuses the existing
  `ShareSheet`.
- Wired `AppRoute.mySubApps` into `RootViews` and added a "My Sub-Apps" entry under
  Settings → Tools.

**Next iteration:** F2 — Registry browse/install/rate; install flow with permission
review.

### F2 — Registry browse/install/rate (done)
- Added `Platform/SubAppRegistryService.swift`: a `SubAppRegistryService` protocol
  (`featured()` / `search(_:)`, async so a network impl drops in) + a
  `BundledSubAppRegistryService` that serves curated `RegistrySpecs` (Water Intake,
  Gratitude Journal, Reading Log), each **signed at runtime** so install matches the
  remote path exactly. `SubAppRegistryStore` persists the user's star ratings +
  installed ids in UserDefaults.
- Added `Views/SubAppRegistryView.swift` (`AppRoute.subAppRegistry`): search, browse
  cards with community rating + category, a permission-review **install sheet**, and a
  per-app 1–5 star rating control once installed. Install re-encodes + re-verifies the
  signed package (never trusts the in-memory listing), guardrail-reviews it, persists
  via `UserSubAppStore`, and registers routes.
- Wired `AppRoute.subAppRegistry` + a "Sub-App Store" entry under Settings → Tools.

**Next iteration:** F3 — Moderation/safety + versioned updates for installed
sub-apps.

### F3 — Moderation + versioned updates (done)
- Added `Platform/SubAppModerator.swift`: a `moderate(_:)` pass returning a single
  `ModerationVerdict` (`approved` / `flagged([reasons])` / `rejected([reasons])`). It
  runs validation + guardrails first, then a deep all-text scan (names, labels,
  selection options, screen titles) with **reject** phrases (medical/harmful/deceptive)
  and **flag** phrases (borderline wellness claims). Deterministic + local for v1; the
  backend can swap the body for a server moderation call with the same verdict shape.
- Wired moderation into every install path: the registry **install/update** and the
  file **import** flow both reject disallowed specs and surface flag reasons in the
  confirmation banner.
- Versioned updates: `SubAppRegistryStore` now records the installed version per
  listing and exposes `updateAvailable(for:)`. The store view shows an **Update to
  vX.Y.Z** button when the registry offers a newer version of an installed sub-app.

**Next iteration:** G1 — Per-sub-app analytics, error recovery, accessibility audit,
tests.

### G1 — Analytics, recovery, tests (done)
- Added `Services/SubAppAnalytics.swift`: privacy-preserving on-device per-sub-app
  counters (opens, records created, recoverable errors, last-used). No content is
  recorded. The spec runtime reports `.opened` on appear and `.recordCreated` on new
  saves; `MySubAppsView` surfaces a per-app usage line.
- Error recovery: the SwiftData record store already degrades gracefully (all
  fetch/decode/save are non-fatal `try?`), so a corrupt payload yields an empty record
  rather than a crash — covered implicitly by the runtime + verified design.
- Accessibility: registry star controls + usage lines carry explicit VoiceOver
  labels/values (continuing the per-iteration accessibility work from Phase B).
- Tests: added `PulseLoopTests/SubAppPlatformTests.swift` (18 tests, all passing)
  covering the spec validator (slugs, entity refs, emoji icons, empty entities), the
  signed package round-trip + **tamper detection** + corrupt-input handling, the
  moderation pass (approve/flag/reject + reserved-id), and the credits ledger
  (initial grant, debit math, affordability, grant, authoritative sync). Also fixed a
  pre-existing `@MainActor` isolation break in `CoachNotificationTests` that blocked
  the test target from compiling.

**ROADMAP COMPLETE.** All phases A–G are done. PulseLoop is now a modular sub-app
platform: every built-in feature is a `SubApp`; a declarative spec runtime renders +
persists dynamic sub-apps; the AI Builder designs guard-railed sub-apps; AI usage is
metered, purchasable, and enforced (local + backend-proxy seam); sub-apps export/
import as signed packages, install from a moderated registry with versioned updates;
and the safety-critical seams are covered by tests. Build: ✅ `BUILD SUCCEEDED`.
Tests: ✅ 18/18 in `SubAppPlatformTests`.

### H1 — AWS Bedrock (Claude) coach provider (done)
- Added a new `CoachProviderMode.bedrock`: the coach can run directly against
  **Anthropic Claude on AWS Bedrock** using on-device IAM credentials, no PulseLoop
  server required. Defaults to the latest Claude Opus inference profile
  (`us.anthropic.claude-opus-4-1-20250805-v1:0`), region + model id user-editable in
  Coach settings.
- New files under `PulseLoop/Coach/Bedrock/`:
  - `AWSSigV4Signer.swift` — pure-Swift (CryptoKit) AWS Signature V4 signer for the
    `bedrock-runtime` `InvokeModel` POST (canonical request → string-to-sign →
    signing key → Authorization header; path-encodes the model id's `:`/`.`).
  - `BedrockCredentialsStore.swift` — Keychain-backed store for the access key id +
    secret + optional session token (secret never touches source/UserDefaults).
  - `BedrockResponsesClient.swift` — a `ResponsesClient` that translates the OpenAI
    Responses wire format ⇄ Anthropic Messages: `input`/`function_call_output` →
    `messages`/`tool_result`, OpenAI tools → Anthropic `input_schema` tools, strict
    `text.format` schema → a system instruction (Anthropic has no native equivalent;
    the orchestrator's JSON-repair round covers residual risk). Because Bedrock is
    **stateless** (no `previous_response_id`), the client keeps the running transcript
    in an in-memory actor cache keyed by the response id and rebuilds it each round.
- Wiring: `CoachSettings` gained `bedrockRegion` + `bedrockModelID` (tolerant decode);
  `CoachFeatureFlags` added `bedrockConfigured` + status line; `CoachViewModel.makeClient`
  selects the Bedrock client when in `.bedrock` mode with complete credentials;
  `CoachSettingsSection` added a credentials/region/model entry card (Keychain-backed,
  show/hide secret).
- Credits are still metered locally for this BYO path (same transitional model as
  `userOpenAIKey`).

**Caveats / follow-ups**
- Structured-output fidelity relies on prompt-injected schema + JSON repair rather
  than a hard `text.format` guarantee; watch for malformed final JSON on complex turns.
- Bedrock `web_search` has no Anthropic analogue and is skipped in tool translation.
- No unit tests yet for the SigV4 signer or the translation layer (recommended next).
- Legacy `AIService` (meal scan, command palette, etc.) still uses OpenRouter and is
  unaffected by this change.

Build: ✅ `BUILD SUCCEEDED` (iOS Simulator), installed + launched.

### E3 — backend-proxy enforcement seam (done)
- Added `Coach/OpenAI/BackendProxyResponsesClient.swift`: a `ResponsesClient` that
  POSTs the verbatim Responses body to `{baseURL}/v1/coach/responses` with a session
  bearer token. The server holds the OpenAI key and is the authoritative credit
  ledger. Handles `402 Payment Required` (→ `ResponsesError.insufficientCredits`) and
  adopts a server-reported `pulseloop_credits.balance` via
  `CreditsLedger.syncAuthoritativeBalance(_:)`.
- `CoachProviderMode.backendProxy` is now live: `CoachFeatureFlags.coachEnabled`
  returns true when a valid `backendProxyURL` is set (no longer a hard `false`), and
  the status line reflects it. Added `backendProxyURL` to `CoachSettings` (tolerant
  decode) + a URL field in the Coach settings section (shown only in proxy mode).
- `CoachViewModel` now (a) **enforces credits up front** — refuses an LLM turn and
  posts a "you're out of credits" assistant message when `canAfford(.coachTurn)` is
  false (server still enforces authoritatively in proxy mode), and (b) selects the
  transport per provider mode via `makeClient(...)`.

**Phase E complete.** AI usage is metered, purchasable, balance-visible, and now
enforced — locally for BYO-key and server-authoritatively through the proxy seam.

**Next iteration:** F1 — Export/import signed `SubAppSpec`.
