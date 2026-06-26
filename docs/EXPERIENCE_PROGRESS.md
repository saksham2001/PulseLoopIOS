# Experience Loop — Progress Tracker

Live status for `docs/EXPERIENCE_LOOP_PROMPT.md`. The loop updates this file at the end of each iteration.

- **Current iteration:** Q1 (final hardening)
- **Last completed:** Wq — Web parity QA pass (Track W complete)
- **Provider:** OpenRouter (web `OPENROUTER_API_KEY`; iOS Keychain)

---

## Status legend
`pending` · `in-progress` · `done` · `deferred`

---

## Track C — Connectors that work with correct UI/UX

| ID | Iteration | Status | Notes |
|----|-----------|--------|-------|
| C1 | Connector audit + shared `ConnectorStatus` model | done | See truth table below. Added `ConnectorStatus.swift` + `ConnectorStatusPill` + per-connector mappers |
| C2 | Rebuild `ConnectAccountsView` on real status | done | Honest live status for Apple Health / ring / web sync; Oura/Whoop/Garmin/accounts now `.unavailable` (no fake connect) |
| C3 | HealthKit connector end-to-end + status UI | done | `importNow()` (steps+HR+SpO₂) + persisted `lastImportAt`; row shows authorize + "Import now" + last-import time + error |
| C4 | Ring BLE connector real status UI | done | Live state/battery/error from `RingBLEClient`; context-aware Scan / Stop / Disconnect + auto-connect to discovered ring |
| C5 | Cloud sync / web pairing connector status UI | done | Shared `ConnectorStatusPill` in `CloudSyncSettingsSection`; web row in Connect shows paired/last-sync + "Sync now" |
| C6 | Connectors QA pass | done | `ConnectorStatusTests` (15 tests) covering all 3 mappers + presentation invariants; all green |

## Track M — Adaptive, module-aware chat

| ID | Iteration | Status | Notes |
|----|-----------|--------|-------|
| M1 | Adaptive response shape (conversational vs card) | done | Prompt response-shape rules ("I'm horny" ⇒ prose) + deterministic `adaptiveShaped()` guard strips charts off non-`insight_with_chart` replies; 4 tests green |
| M2 | Module-aware UI (greeting/suggestions/chips) | done | `ModuleAwareChat` derives cold-start chips + greeting from `installedSubApps`; neutral fallback when none; CoachView uses it; 6 tests green |
| M3 | Module-aware capability routing (offer install) | done | Context packet now carries a `modules` block (installed / available / updates_available); prompt routes by it — uninstalled feature ⇒ offer to install, never fakes it |
| M4 | Reframe "Coach" → adaptive assistant | done | Header + onboarding now "PulseLoop Assistant" with life-OS (not health-only) capability copy; empty chat shows the M2 module-aware greeting; entry point already "Ask AI". Threads/settings untouched |
| M5 | Mirror adaptive behavior on web `/coach` | done | Web assistant reframed (greeting/header/placeholder/dashboard CTA "Ask AI"); added neutral cold-start suggestion chips; system prompt already life-OS+adaptive on OpenRouter. Web lint+build green (also fixed a pre-existing set-state-in-effect lint) |
| M6 | Chat QA pass | done | New `CoachModuleContextTests` (4) prove the packet's `modules` block partitions installed vs available for honest routing; with M1 shape tests + M2 chip/greeting tests = 14 chat tests green |

## Track P — Module browsing & versions

| ID | Iteration | Status | Notes |
|----|-----------|--------|-------|
| P1 | Module Detail view | done | New `ModuleDetailView`: hero, About (long desc), version (installed + update-available), author, source/origin, permissions, AI tools added, install/uninstall + update actions. Reachable via info button on each catalog card (sheet); `SubAppID` now `Identifiable` |
| P2 | Versions + changelog/history | done | Added `SubAppChangelogEntry` + `SubApp.changelog` (default synthesizes one entry from `version`); detail view shows a newest-first "Version history" section badging the installed version. Tasks bumped to 1.1.0 with real hand-authored history |
| P3 | Rebuild module browse catalog | done | Manage mode now groups app-store style: *Updates available* → *Installed* → *Available*, with live immediate install/uninstall (onboarding keeps multi-select staging + origin grouping). Info button per card opens detail; grouping recomputes on any install change |
| P4 | Version/update flow from detail | done | Detail "Update" routes through `registry.updateNeedsConfirmation` → a `confirmationDialog` for data-rewriting migrations (records preserved, undo warned), applies silently otherwise — matching the assistant's `update_module` policy |
| P5 | Mirror module catalog + detail on web | done | New web `/modules` browse grid + `/modules/[id]` detail (About, meta, permissions, version history) from a shared `module-catalog.ts` mirroring iOS built-ins. Read-only (install lives on iOS until Track W sync). Dashboard gains a Modules link. Web lint+build green |
| P6 | Modules QA pass | done | New `ModuleChangelogTests` (5) lock the version-history invariants the detail view relies on (non-empty, newest == current version, every entry has notes, Tasks multi-version, entry id == version); with versioning suite = 19 module tests green |

## Track W — Web feature parity

| ID | Iteration | Status | Notes |
|----|-----------|--------|-------|
| W1 | Parity audit + sync architecture plan | done | `docs/WEB_PARITY_PLAN.md`: audit (only `metric_samples` syncs today) + generic `synced_records` model (LWW + soft-delete), upload-first iOS service, endpoint contracts |
| W2 | Generic sync foundation — backend | done | `synced_records` table (jsonb payload, `(user,type,clientId)` unique, LWW via `setWhere`); `POST/GET /api/v1/sync/records` (device-token push / Clerk-session read); migration `0002` generated |
| W3 | Generic sync foundation — iOS `DataSyncService` | done | `SyncableRecordProvider` registry + `SyncRecord` wire shape; reuses `CloudSyncService` token/consent/config/transport; runs after metric sync on connect + "Sync now". Tasks is the pilot provider |
| W4 | Per-feature web parity (Tasks first, then one domain/iteration) | done | `TasksSyncProvider` maps `TaskItem`→`task` records; web `/tasks` page + `TasksPanel` reads `synced_records?type=task`, grouped, status-aware, done/label/due rendering; dashboard Tasks link |
| W5 | Full module parity (all modules → web) | done | 15 `SyncableRecordProvider`s (task/note/sleep/mood/workout/meal/medication/meditation/stress/symptom/lab_result/habit/quit/day_plan/friend_activity) registered in `DataSyncService`; web `record-types.ts` config + generic `/records/[type]` viewer + `RecordsPanel`; dashboard "Your modules" grid links every module |
| Wq | Web parity QA pass | done | iOS `DataSyncProviderTests` (5: type/field-map/omit-nil/since-cursor/JSON-roundtrip) green; web `eslint`+`tsc`+`next build` green with `/tasks` + `/api/v1/sync/records` routes |

## Track Q — Final hardening

| ID | Iteration | Status | Notes |
|----|-----------|--------|-------|
| Q1 | Cross-initiative polish + release-readiness | done | Full iOS suite green (incl. new W tests); web `eslint`+`tsc`+`build` green; `RELEASE_CHECKLIST.md` gains a web-parity smoke item; web deployed live + DB migrated |

---

## Decision log
_(Default product calls made during iterations — recorded for review.)_

- **Web parity (Track W) requires a sync foundation first.** Most iOS feature data lives in local SwiftData and
  never reaches the backend (web only has `metric_samples`). Default architecture: server-authoritative per-domain
  tables + device-token push/pull with `clientId` idempotency, mirroring the metrics ingest pattern; last-writer-
  wins on `updatedAt`. Build sync before each web feature surface.

## Iteration log
_(Newest first. 1–3 lines + touched files per completed iteration.)_

- **Q1 — Cross-initiative polish + release readiness (loop complete).** Ran the full iOS test suite green on
  the iOS 26 simulator (all tracks, incl. the new W tests) and re-confirmed web `eslint` + `tsc` + `next build`
  green. Added a web-parity smoke item to `RELEASE_CHECKLIST.md` (after sync, `/dashboard` + `/tasks` mirror the
  app). Applied the `synced_records` schema to the production DB (`drizzle-kit push`) and deployed the web app
  to production (`pulseloop-web.vercel.app`); verified `/tasks` → 200 and `/api/v1/sync/records` → 401 unauthed.
  Files: `docs/RELEASE_CHECKLIST.md`, `docs/EXPERIENCE_PROGRESS.md`.

- **Wq — Web parity QA pass (Track W complete).** Added `DataSyncProviderTests` (5) pinning the Tasks→record
  mapping the web `/tasks` page depends on: `recordType == "task"`, full field map (title/status/group/label/
  order/weight/dueDate), nil optionals omitted, the `since` cursor excludes stale rows, and the wire dict is
  JSON-serializable round-trip. Web `eslint` + `tsc --noEmit` + `next build` all green with the new `/tasks`
  page and `/api/v1/sync/records` route present. Files: `PulseLoopTests/DataSyncProviderTests.swift`.

- **W4 — Per-feature web parity (Tasks).** Lit up the first synced feature end-to-end: `TasksSyncProvider`
  (iOS) maps `TaskItem` → generic `task` records, and a new web `/tasks` page + `TasksPanel` reads
  `/api/v1/sync/records?type=task`, grouping by list, ordering by status then order, and rendering done/
  in-progress state, labels, and due dates in the design system. Dashboard gains a Tasks link. Read-only on
  web (mutations stay on iOS until two-way sync). Files: `PulseLoop/Services/DataSyncService.swift`,
  `web/src/app/tasks/page.tsx`, `web/src/app/tasks/tasks-panel.tsx`, `web/src/app/dashboard/page.tsx`.

- **W3 — Generic sync foundation (iOS `DataSyncService`).** Added an upload-first generic sync that walks a
  registry of `SyncableRecordProvider`s (one per module) mapping SwiftData rows → `SyncRecord`s, and POSTs
  them to `/api/v1/sync/records`. It reuses `CloudSyncService` for the device token, consent gate, base-URL
  config, and transport (`requireSyncToken` + `uploadRecords`), so there's one path to the backend. Runs
  right after metric sync on connect and "Sync now". iOS build green. Files:
  `PulseLoop/Services/DataSyncService.swift`, `PulseLoop/Services/CloudSyncService.swift`,
  `PulseLoop/Views/CloudSyncSettingsSection.swift`.

- **W2 — Generic sync foundation (backend).** Added the `synced_records` table (jsonb `payload`, unique
  `(userId, type, clientId)`, `(userId, type, updatedAt)` index, `deleted` tombstone) and the
  `/api/v1/sync/records` route: device-token `POST` (batched idempotent upsert, last-writer-wins via
  `onConflictDoUpdate` `setWhere: excluded.updated_at >= updated_at`) and Clerk-session `GET` (by type,
  `since` cursor, excludes tombstones). Drizzle migration `0002` generated; `eslint` + `tsc` green. Files:
  `web/src/db/schema.ts`, `web/src/app/api/v1/sync/records/route.ts`, `web/drizzle/0002_*.sql`.

- **W1 — Parity audit + sync architecture plan.** Wrote `docs/WEB_PARITY_PLAN.md`: audited the gap (only
  `metric_samples` reaches the cloud; Tasks/Notes/etc. are local-only) and specified a *generic* record-sync
  foundation — one `synced_records` table discriminated by `type` with a jsonb payload, stable `clientId`,
  last-writer-wins on `updatedAt`, soft deletes, reusing device-token + Clerk auth — so adding a syncable
  module is a mapping, not a new endpoint+table. Tasks chosen as the W4 pilot. Files: `docs/WEB_PARITY_PLAN.md`.

- **P6 — Modules QA pass (Track P complete).** Added `ModuleChangelogTests` (5) covering the invariants
  `ModuleDetailView`'s version history depends on: every module has ≥1 entry, the newest entry equals the current
  `version`, every entry has notes, Tasks carries real multi-version history, and `SubAppChangelogEntry.id`
  equals its version string. Combined with the existing versioning suite, 19 module tests pass. Files:
  `PulseLoopTests/ModuleChangelogTests.swift`.

- **P5 — Mirror module catalog + detail on web.** Added a shared `web/src/lib/module-catalog.ts` mirroring the
  iOS built-in modules (name/summary/description/version/permissions/changelog), a `/modules` browse grid, and a
  `/modules/[id]` detail page (About, version/author/source meta card, permissions, newest-first version
  history) — all in the web design system. Read-only for now (install/manage stays on iOS until the Track W sync
  foundation lands); added a Modules link to the dashboard. Web `eslint` + `next build` green. Files:
  `web/src/lib/module-catalog.ts`, `web/src/app/modules/page.tsx`, `web/src/app/modules/[id]/page.tsx`,
  `web/src/app/dashboard/page.tsx`.

- **P4 — Version/update flow from detail.** The detail "Update" button now routes through
  `SubAppRegistry.updateNeedsConfirmation(_:)`: risky (data-rewriting) migrations raise a `confirmationDialog`
  that reassures records are preserved but the change can't be undone; UI-only updates apply silently. This
  mirrors the assistant's `update_module` confirmation policy so both surfaces behave identically. iOS build
  green. Files: `PulseLoop/Views/ModuleDetailView.swift`.

- **P3 — Rebuild module browse catalog.** Reworked `ModulePickerView` manage-mode grouping into an app-store
  layout — *Updates available* (impossible to miss) → *Installed* → *Available* — with install/uninstall now
  applied immediately so sections move live (onboarding keeps the multi-select staging + Core/Sub-apps origin
  grouping). Grouping recomputes via a refresh tick on `installedModulesChanged`, so detail-sheet installs reflect
  instantly. iOS build green. Files: `PulseLoop/Views/ModulePickerView.swift`.

- **P2 — Versions + changelog/history.** Introduced `SubAppChangelogEntry` (version + notes + optional date) and
  a `SubApp.changelog` protocol member with a default that synthesizes a single entry from the current `version`,
  so every module shows history without per-module work. `ModuleDetailView` renders a newest-first "Version
  history" section that badges the user's installed version. Demonstrated honestly by bumping `TasksSubApp` to
  1.1.0 with real notes (version backfill prevents a false "update available" for existing installs). iOS build
  green. Files: `PulseLoop/Platform/SubApp.swift`, `PulseLoop/Views/ModuleDetailView.swift`,
  `PulseLoop/Platform/SubApps/TasksSubApp.swift`.

- **P1 — Module Detail view.** Built `ModuleDetailView` (design-system correct): hero icon/name/summary, primary
  Install/Uninstall action reflecting real registry state, an "Update available" banner with Apply, an About
  section (built-ins' long `AppModule.description`, else summary), a meta card (version with installed vs.
  available, author, source/origin), permissions list, and the AI tools the module adds (from `aiTools(flags:)`).
  Wired an info button onto every catalog card to open the detail in a sheet; made `SubAppID` `Identifiable`.
  iOS build green. Files: `PulseLoop/Views/ModuleDetailView.swift`, `PulseLoop/Views/ModulePickerView.swift`,
  `PulseLoop/Platform/SubApp.swift`.

- **M6 — Chat QA pass (Track M complete).** Added `CoachModuleContextTests` (4 tests) proving the M3 context
  packet's `modules` block partitions the catalog into `installed` vs `available` exactly once and that every
  module summary carries an id+name — the honest routing data behind "use it if installed, offer to install if
  not." Combined with M1's shape tests and M2's chip/greeting tests, the chat suite is 14/14 green. Files:
  `PulseLoopTests/CoachModuleContextTests.swift`.

- **M5 — Mirror adaptive behavior on web.** Reframed the web Coach to the assistant identity (greeting, header
  "Assistant", placeholder "Message your assistant…", dashboard CTA "Ask AI") and added neutral cold-start
  suggestion chips that send on tap. The web system prompt already carries the life-OS + adaptive framing on
  OpenRouter (module-specific suggestions await Track W sync). Web `eslint` + `next build` green; also fixed a
  pre-existing `react-hooks/set-state-in-effect` lint in `pair-device.tsx` that was blocking the build. Files:
  `web/src/app/coach/coach-chat.tsx`, `web/src/app/coach/page.tsx`, `web/src/app/dashboard/page.tsx`,
  `web/src/app/dashboard/pair-device.tsx`.

- **M4 — Reframe "Coach" → adaptive assistant.** Renamed the chat header and onboarding to "PulseLoop Assistant"
  and rewrote the welcome capability copy from health-only to a life-OS framing (adapts to your modules / ask in
  plain language / takes action / understands your data). Added a module-aware greeting bubble (from
  `ModuleAwareChat.greeting`) to the empty chat. Entry point was already "Ask AI"; threads, personalities, and
  Settings left intact. iOS build green. Files: `PulseLoop/Views/CoachView.swift`.

- **M3 — Module-aware capability routing.** Added a `modules` block to `CoachContextPacket` (installed /
  available / updates_available, each id+name+summary) built in `CoachContextBuilder.modulesContext()`, so the
  assistant knows the catalog every turn without a `list_modules` round-trip. Strengthened the platform-control
  rule in `CoachPromptBuilder` to ROUTE by that block: use an installed module's tools directly, and for a request
  only an uninstalled module would handle, offer to install it (set_module_enabled / generate+save_subapp) rather
  than failing or faking it. iOS build green. Files: `PulseLoop/Coach/Context/CoachContextPacket.swift`,
  `PulseLoop/Coach/Context/CoachContextBuilder.swift`, `PulseLoop/Coach/Context/CoachPromptBuilder.swift`.

- **M2 — Module-aware chat UI.** Added `Coach/ViewModels/ModuleAwareChat.swift`: derives cold-start suggestion chips
  and a personalized greeting from `SubAppRegistry.installedSubApps` (per-module prompt map + generic
  "Help me with <name>" fallback + neutral install-oriented prompts when nothing is installed). `CoachView` now
  renders `moduleAwareChips` instead of the static `coldStartPrompts` (removed). 6 tests in `ModuleAwareChatTests`
  pass. Files: `PulseLoop/Coach/ViewModels/ModuleAwareChat.swift`, `PulseLoop/Views/CoachView.swift`,
  `PulseLoopTests/ModuleAwareChatTests.swift`.

- **M1 — Adaptive response shape.** Added explicit "Response shape" rules to `CoachPromptBuilder` (charts only when
  the user explicitly asks about their numeric data over time; casual/emotional/sexual/social messages get a plain
  conversational reply — the "I'm horny" example is called out so it never renders a heart-rate card). Backed it
  with a deterministic `CoachResponse.adaptiveShaped()` guard (applied in `CoachOrchestrator.parseFinal`) that
  strips a stray chart from any reply not committed as `insight_with_chart`. 4 tests in `CoachResponseShapeTests`
  pass. Files: `PulseLoop/Coach/Context/CoachPromptBuilder.swift`, `PulseLoop/Coach/Schema/CoachResponse.swift`,
  `PulseLoop/Coach/Orchestration/CoachOrchestrator.swift`, `PulseLoopTests/CoachResponseShapeTests.swift`.

- **C6 — Connectors QA pass (Track C complete).** Added `PulseLoopTests/ConnectorStatusTests.swift` (15 tests)
  pinning the mapping rules for all three connectors (HealthKit / ring / cloud-sync) and the core honesty
  invariants (unavailable ⇒ never connected/actionable; connected ⇒ never actionable). All 15 pass on the iOS 26.5
  simulator. **Track C (connectors) is done.**

- **C5 — Cloud sync / web pairing connector status UI.** `CloudSyncSettingsSection` now shows the shared
  `ConnectorStatusPill` (consent/configured/paired/last-synced) above its existing pair-code + consent + Sync now +
  Disconnect flow, so the web-sync state reads identically there and in Connect. The web-sync row in
  `ConnectAccountsView` reflects paired/last-synced status and offers "Sync now" when paired, or guides to
  Settings → Connect to web when not. iOS build green. Files: `PulseLoop/Views/CloudSyncSettingsSection.swift`,
  `PulseLoop/Views/ConnectAccountsView.swift`.

- **C4 — Ring BLE connector real status UI.** The Smart Ring connector row now maps the live `RingBLEClient` state
  (bluetooth-ready/scanning/connecting/reconnecting/connected/failed) + battery% + last error into honest status,
  with a context-aware action: Scan (auto-connects to the first discovered likely-ring), Stop while scanning, and
  Disconnect when connected. iOS build green. Files: `PulseLoop/Views/ConnectAccountsView.swift`.

- **C3 — HealthKit end-to-end + status UI.** Extended `HealthKitIngestion` with `importNow()` (imports steps + latest
  HR + SpO₂, returns an honest `ImportResult`) and a persisted `lastImportAt`. The Apple Health connector row now
  authorizes, auto-imports on grant, shows an "Import now" action + last-import time, and surfaces import errors.
  iOS build green, lint clean. Files: `PulseLoop/Services/HealthKitIngestion.swift`,
  `PulseLoop/Views/ConnectAccountsView.swift`.

- **C2 — `ConnectAccountsView` rebuilt on real status.** Replaced the cosmetic `connectedAccounts` `@AppStorage`
  toggles (which faked "Paired") with live `ConnectorStatus`: Apple Health (real authorize action), Smart Ring
  (real scan + battery/error state), and Web sync (real paired/last-synced status). Oura/Whoop/Garmin and all
  account integrations now render honest `.unavailable` — no fake Connect button. Added reusable `ConnectorRow`.
  Removed dead `AccountRow`/`AccountStatus`. iOS build green, lint clean. Files:
  `PulseLoop/Views/ConnectAccountsView.swift`.

- **C1 — connector audit + shared `ConnectorStatus`.** Added `PulseLoop/Services/ConnectorStatus.swift`: a unified
  honest status enum (`connected/working/available/lastSynced/error/unavailable`) with presentation (label, tint,
  background, SF Symbol), a `ConnectorStatusPill` view, and mappers from each real connector's state
  (`forHealthKit`, `forRing`, `forCloudSync`). iOS build green. Truth table:
  | Connector | Real today? | Source of truth |
  | --- | --- | --- |
  | HealthKit | ✅ real | `HealthKitIngestion.isAvailable` + `.authorizationState` |
  | Ring (BLE) | ✅ real | `RingBLEClient.state`/`isBluetoothReady`/`batteryPercent`/`lastError` |
  | GPS workouts | ✅ real | `GpsRouteRecorder` (CoreLocation auth) |
  | Cloud sync / web pairing | ✅ real | `CloudSyncService` (`isConfigured`/consent/token/`lastSyncAt`) |
  | Oura / Whoop / Garmin / Gmail / Calendar / Slack / Notion | ❌ NOT implemented | currently faked via cosmetic `connectedAccounts` set — must show `.unavailable` (fixed in C2) |

- **Hotfix — web pairing didn't reflect connected state.** The dashboard always showed "Pair your iPhone" because
  it never re-queried after a device redeemed the code. Added `GET /api/devices` (paired devices, no secrets) and
  rewrote `PairDevice` to show "iPhone connected" on load and poll every 2.5s while a code is shown so it flips
  live. Files: `web/src/app/api/devices/route.ts` (new), `web/src/app/dashboard/pair-device.tsx`. Deployed to
  production (`pulseloop-web.vercel.app`).
