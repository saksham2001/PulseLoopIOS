# HARDENING_PROGRESS — Production Hardening

Live tracker for `docs/HARDENING_LOOP_PROMPT.md`. Status: `pending` / `in progress` / `done`.

---

## Phase A — Protect user data
- **A1** `done` — Added `App/AppLog.swift`: `AppLog` facade over `os.Logger` (subsystem `xyz.sakshambhutani.PulseLoop`, categories persistence/network/coach/health/ring/ui). No behavior change.
- **A2** `done` — Added `Persistence/PersistenceError.swift` with `ModelContext.saveOrLog(_:)`/`saveOrThrow(_:)` + `PersistenceError`. Migrated high-value `try? save` sites: `SubAppPersistence`, `CoachViewModel` (×5), `PendingActionExecutor` (×5), `VoiceCaptureRouter`. Tests in `PulseLoopTests/PersistenceHelperTests.swift` (5).
- **A3** `done` — Added `SchemaV1: VersionedSchema` (= current `allModels`) + `PulseLoopMigrationPlan: SchemaMigrationPlan` (single baseline version, no stages yet) wired into `ModelContainerFactory.make`. Dynamic sub-app `DynamicSubAppRecord` is JSON-payload/migration-tolerant. Existing stores + all tests load unchanged.
- **A4** `done` — `PulseLoopApp.init` no longer `fatalError`s on store-load failure: logs via `AppLog.persistence.fault`, falls back to a temporary in-memory container, and shows a dismissible `LaunchRecoveryBanner` (design-system styled, alert color, a11y label). Only an in-memory-creation failure (should never happen) remains fatal.

## Phase B — Make failures visible
- **B1** `done` — Swept service + Coach-tool layer `try? save` to `saveOrLog`: Coach tools (`PlatformControlTools`, `ActionTools`, `DailyLifeTools`, `TaskTools`, `NoteTools`, `ProtocolTools`, `MemoryTools`), `QuitProgramSubApp`, and services (`RingSyncCoordinator`, `PulseEventBus`, `LiveWorkoutManager`, `WorkoutSensorPollingService`, `PulseServices` ×7, `PermissionGateService` ×2, `CoachSummaryService` ×2, `CoachNotificationService`, `DailyLearningService`, `SeedData` ×4). View-layer saves deferred (lower risk). No behavior change.
- **B2** `done` — Added `DesignSystem/ErrorToast.swift`: `ErrorPresenter` (@Observable singleton) + `.errorToast()` root modifier (design-system styled, auto-dismiss, a11y). `saveOrLog(_:surface:)` gained an opt-in `surface` flag that shows a user-facing toast on failure; wired to the Coach send path (user-initiated write). Attached `.errorToast()` at app root.

## Phase C — Honest stubs
- **C1** `done` — **Decision: implemented real HealthKit** (the `com.apple.developer.healthkit` entitlement already exists). `HealthKitIngestion` now does real `HKHealthStore` authorization + sample queries (HR, SpO2, steps, sleep) guarded by `canImport(HealthKit)` + `isHealthDataAvailable()`; reports `HealthAuthorizationState` (`unavailable`/`notAuthorized`/`authorized`) so simulator/unentitled devices show an honest state instead of fake data. Failures logged via `AppLog.health`; sync save uses `saveOrLog`. Added `NSHealthShareUsageDescription`/`NSHealthUpdateUsageDescription` to Info.plist.
- **C2** `done` — `AccountConnector` now declares `isDemo` (defaults `true`) so the demo Gmail/Calendar/Slack stubs are self-describing; `ConnectAccountsView` already gates accounts as "Coming soon". Replaced emoji icons (✉︎/📅/#/📝/⌚/💍/➰ and demo inbox icons) with SF Symbols per the design system; `AccountRow` renders `Image(systemName:)`. Connector save uses `saveOrLog`. (Real OAuth remains a follow-up; nothing in the UI implies a live link.)

## Phase D — Harden network edges
- **D1** `done` — Added `Services/HTTPTransport.swift`: `HTTPTransport` seam (`URLSession` conforms) + `NetworkRetry.send` (exponential backoff on transport errors / 5xx / 429, cancellation-aware, logs via `AppLog.network`), generalized from `MuapiClient.sendWithRetry`. Tests in `PulseLoopTests/NetworkRetryTests.swift` (6, injectable fake transport).
- **D2** `done` — Added `ResponseCache` (thread-safe in-memory TTL cache, 1h) to `HTTPTransport.swift`. `OpenFDAService` + `OpenFoodFactsService` now route through `NetworkRetry.send` with caching; failures logged instead of silently returning empty (still return empty/nil to callers).
- **D3** `done` — `CloudSyncService.baseURL` → `resolvedBaseURL: URL?`: DEBUG allows localhost; release disables sync (returns nil + logged warning) when URL is missing/invalid/local instead of defaulting to `http://localhost:3000`. Added `SyncError.notConfigured` + `isConfigured`; `pair`/`sync`/`upload` guard on it.
- **D4** `done` — Migrated `AIService.complete(...)` response-envelope parse from `JSONSerialization` to a `Codable` `ChatCompletionResponse` via `decodeChatContent(_:)` — the template for converting the remaining ~20 `JSONSerialization` sites (follow-up).

## Phase E — Guard against regressions
- **E1** `done` — Added shared scheme `PulseLoop.xcscheme` (was unshared, blocking CI) + `.github/workflows/ci.yml` running `xcodebuild clean test` on `macos-15` / iPhone 16 Pro simulator, with result-bundle artifact upload.
- **E2** `done` — Added `PulseLoopTests/SmokeFlowTests.swift` (4 headless tests): fresh install → empty catalog, install module → appears in `installedSubApps` + non-decreasing Coach tools, uninstall reverts, Coach conversation persists. (XCUITest target tracked as follow-up.) `NetworkRetryTests` fake transport converted to an `actor` to clear Swift-6 lock warnings.
- **E3** `done` — Added `PulseLoop/Localizable.xcstrings` (string catalog) and migrated the Home empty-state copy (`home.empty.title`/`.body`/`.button`) to localized `Text(_:comment:)` keys — establishing the localization pattern without a mass migration.
- **E4** `done` — Accessibility pass on the Home empty state: decorative icon `accessibilityHidden`, install button gets an explicit label/hint/`.isButton` trait. (Launch recovery banner + error toast already a11y-labeled in A4/B2.)

## Phase F — Structural cleanup (after A–E)
- **F1** `done` — Moved the largest knowledge blob (`SupplementKnowledge.database`, 27 entries) to a bundled JSON resource. `SupplementInfo` is now `Codable`; `database` loads from `PulseLoop/Resources/supplements.json` (auto-bundled via the synchronized file group) and falls back to the in-source `inSourceDatabase` if the resource is missing/undecodable (logged via `AppLog.persistence`). JSON is generated from the in-source array via `SupplementCatalogTests.testRegenerateBundledJSON` (no hand-transcription); round-trip + non-empty load verified by tests. Tuple-based interaction/meal blobs left in-source (intertwined query logic).
- **F2** `done` — Split the 2317-line `TrackerView.swift` monolith: extracted the 9 standalone supporting views/models (`StatCard`, `DeviceRow`, `TimelineContainer`, `TimelineRow`, `ProtocolScanCameraView`, `MacroBar`, `MealRow`, `RoutineGridCard`, `AISupplementProfile`, `ProtocolItem`, `GroupedProtocolSection`) into `Views/TrackerSupportingViews.swift` (371 lines), leaving `TrackerView.swift` at 1949. Also finished the deferred Phase-B sweep here: the 4 view-layer `try? modelContext.save()` sites (meal/medication/protocol logging) now use `saveOrLog("tracker", surface: true)`. Build + all 178 tests green.

---

### Log
- (init) Tracker created from roadmap.
- Phases A–F complete. Full suite (178 tests) green. Build SUCCEEDED.
