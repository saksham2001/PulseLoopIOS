# PulseLoop → Production Hardening — Loop Prompt

> **How to use this file.** Paste the section titled **"THE LOOP PROMPT"** (§4) into Claude (Cursor agent) as a single message at the start of each working session. Claude does exactly one iteration, updates the tracker `docs/HARDENING_PROGRESS.md`, and stops. Re-run to advance. The rest of this document (Context, Targets, Roadmap, Guardrails) is reference the prompt points Claude at — keep it in the repo.

---

## 0. North-Star Vision (the fixed mission — never changes between iterations)

Take PulseLoop from "excellent prototype" to **shippable, resilient product** without regressing any existing feature. The app already has a strong AI Coach, an installable sub-app platform, a real BLE ring client, a mature design system, and ~160 logic tests. The mission is to close the **production-readiness gaps** that would lose user data, hide failures, crash on upgrade, or ship stubbed features as if they were real.

**The five pillars (fixed priority order):**

1. **Never lose user data.** Add SwiftData schema versioning + a migration plan so a model change can never crash existing users at the launch-time `fatalError`. Replace silent `try? context.save()` data loss with a safe-save helper that logs and surfaces failures.
2. **Make failures visible.** Introduce structured logging (`os.Logger`) and a small error-surfacing pattern. No silent `try?` on anything that matters (saves, network, decode). Failures must be logged and, where user-facing, shown.
3. **No stub masquerading as real.** Either implement the load-bearing stubs (`HealthKitIngestion`, `AccountConnector` OAuth) or gate them behind an explicit, honest "Not connected / Coming soon" state so the UI never implies data it doesn't have.
4. **Harden the edges.** Add caching + retry/backoff to network services (model on the solid `MuapiClient` pattern), fix the `localhost:3000` cloud-sync default, and consolidate the redundant AI stacks / hand-rolled JSON parsing toward `Codable`.
5. **Guard against regressions.** Add CI (`xcodebuild test`) and smoke UI tests for the critical flows (fresh-install onboarding, install a module, open Coach). Standardize accessibility labels and add localization scaffolding.

**Non-negotiables across every iteration:**
- The app must **always build and run** at the end of each iteration. Never leave the working tree broken. Existing tests must stay green.
- **No behavior regressions.** Hardening must not change a feature's happy-path behavior; it adds safety, logging, and recovery around it.
- **Backward-compatible data.** All SwiftData changes are additive/lightweight (defaulted optional fields, tolerant decoders) and covered by the new migration plan. Never drop user data.
- **Design system is law.** Any new/changed UI uses `PulseColors` / `PulseFont` / `PulseRadius` / `PulseLayout` and components from `App/AppTheme.swift` + `DesignSystem/Components.swift`. Follow `.cursor/rules/design-system.mdc`. SF Symbols only, no emoji in rendered UI, primary buttons black, accent used sparingly.
- **No secrets in source.** AI/provider keys stay in Keychain. The legacy plaintext key handling in `Services/AIService.swift` must not spread.
- **Small, reversible steps.** One shippable iteration at a time; prefer additive helpers over rewrites.

---

## 1. Codebase Context (real anchors — verify before using; do not invent names)

**Stack:** SwiftUI + SwiftData. Entry `PulseLoop/PulseLoopApp.swift` → `RootAppView` (`Views/RootViews.swift`). ~205 Swift files, ~52k lines under `PulseLoop/`.

**Persistence (pillar 1 anchors):**
- `Persistence/ModelContainerFactory.swift` — builds one `Schema` from `coreModels` (~55 listed types) **plus** `SubAppRegistry.shared.allModels`, de-duped by `ObjectIdentifier`; supports `inMemory` for tests. **No `VersionedSchema` / `SchemaMigrationPlan` today.**
- `PulseLoop/PulseLoopApp.swift:~32` — container creation failure currently calls `fatalError` (the crash-on-upgrade risk).
- `@Model` types (~66): `Models/LifeOSModels.swift` (~37), `Models/PulseModels.swift` (~18), `Models/FitnessModels.swift` (~6), Coach models (`Coach/Summaries/CoachSummary`, `Coach/Learnings/DailyLearning`, `Coach/Notifications/CoachNotificationModels`), and `Platform/SubAppPersistence.swift` (`DynamicSubAppRecord` + 1).
- Sub-app dynamic data is one generic `DynamicSubAppRecord` table.
- `Persistence/SeedData.swift` — seeds a demo profile ("Rey") + ~90 days of synthetic data on first launch; `summary.isDemo` propagates into Coach context.

**Silent-failure hot spots (pillar 2 anchors):** `try?` is used in ~90 files. Heaviest: `Services/Repositories.swift`, `Services/AIService.swift`, `Coach/Tools/DailyLifeTools*`, `Platform/SubAppPersistence.swift`, `Views/NoteEditorView.swift`, `Views/TasksView.swift`/`FriendsView.swift`/`InboxView.swift`/`JournalView.swift`, `Services/RingSyncCoordinator.swift`, `Coach/ViewModels/CoachViewModel.swift`, `Services/AccountConnector.swift`, `Services/HealthKitIngestion.swift`. Many are `try? context.save()`. Structured logging exists in ~1 place only (`WorkoutLiveActivityService` via `os.Logger`).

**Stubs (pillar 3 anchors):**
- `Services/HealthKitIngestion.swift` — every fetch returns `nil` (`// In production: query HK…`); `requestAuthorization()` is a no-op. **No real `HKHealthStore` usage anywhere.**
- `Services/AccountConnector.swift` — Gmail/Calendar/Slack are hardcoded demo data; `authorize()` returns `true` without OAuth; `ExtractionPipeline.extract(...)` returns `[]`. Header: "All implementations are stubbed with demo data for simulator use."

**Network services (pillar 4 anchors):** all `URLSession` + async/await.
- `Services/AIService.swift` (~903 lines) → OpenRouter; hand-rolled `JSONSerialization` parsing; no retry. Keys via Keychain → env → Info.plist.
- Coach `ResponsesClient`s (`Coach/.../OpenAIResponsesClient`, `BackendProxyResponsesClient`, `BedrockResponsesClient`) → typed `ResponsesError`; no retry.
- `Services/OpenFDAService.swift`, `Services/OpenFoodFactsService.swift` → catch→empty; **no cache, no retry**.
- `Services/MuapiClient.swift` → **the reference pattern**: `sendWithRetry` exponential backoff on network/5xx/429, submit-then-poll, injectable `MuapiTransport` for tests.
- `Services/CloudSyncService.swift` → base URL from Info.plist `PULSELOOP_WEB_URL`, **defaults to `http://localhost:3000`**; typed `SyncError`.

**Quality/regression anchors (pillar 5):** `PulseLoopTests/` has 17 files (~160 `func test`), strong on logic (Coach, platform, ring decoder, metrics) but **no UI tests, no `.github/workflows`, no fastlane**. Test helper: `PulseLoopTests/PulseLoopTestSupport.swift`. Accessibility labels appear in ~22 of ~53 view files; reduce-motion is handled (`ComfortPrefs.reduceMotion` + `motionReduced` env). **Zero `NSLocalizedString`/`String(localized:)`** — all UI is hardcoded English.

**Design system:** `App/AppTheme.swift` (~764), `DesignSystem/Components.swift` (~704), named color assets, custom fonts (Hanken Grotesk, Newsreader), `.cursor/rules/design-system.mdc`, a component-gallery route.

**Largest files (refactor targets):** `Views/TrackerView.swift` (~2,317), `Services/PeptideKnowledge.swift` (~1,800), `Views/FriendsView.swift` (~1,333), `Views/HomeView.swift` (~1,296), `Views/NoteEditorView.swift` (~1,242), `Models/LifeOSModels.swift` (~1,172). The big knowledge blobs (`PeptideKnowledge`, `SupplementKnowledge`, `MedicationKnowledge`) are hardcoded data that could move to bundled JSON.

---

## 2. Architecture Target (what we are building toward)

### 2.1 Versioned schema + migration (pillar 1)
- Introduce a `VersionedSchema` (e.g. `SchemaV1`) capturing the **current** model set, and a `SchemaMigrationPlan` wired into `ModelContainerFactory`. The first migration stage is identity (V1 → V1) so existing stores load unchanged; this establishes the seam so future changes add a stage instead of crashing.
- Replace the launch-time `fatalError` with a **graceful recovery path**: attempt load → on failure, log + present a recovery screen (retry / reset-with-export) rather than crashing. Keep `inMemory` test path working.
- Sub-app `DynamicSubAppRecord` is generic (JSON-ish payload), so it is migration-tolerant by design — document that and ensure it's in the versioned schema.

### 2.2 Safe save + logging (pillars 1 & 2)
- Add a tiny logging facade, `AppLog` (wrapping `os.Logger` with subsystem `xyz.sakshambhutani.PulseLoop` and per-area categories: `persistence`, `network`, `coach`, `health`, `ring`, `ui`). One file, no third-party deps.
- Add a `ModelContext.saveOrLog(_ area:)` helper (and/or `PersistenceError`) that replaces `try? context.save()`: on failure it logs the error with context and returns a `Bool`/throws so callers can react. Migrate the highest-value `try? context.save()` sites first (Coach, persistence, repositories, capture).
- Establish the pattern: network/decoding `try?` that hides a failure becomes a `do/catch` that logs via `AppLog` and returns a typed result; "best-effort, truly ignorable" `try?` may stay but should be commented as intentional.

### 2.3 Honest stubs (pillar 3)
- `HealthKitIngestion`: either implement real `HKHealthStore` authorization + queries for the core types (HR, HRV, SpO2, steps, sleep) behind the existing async API, **or** make the stub explicit — a `HealthDataSource` with a `.notAuthorized`/`.unavailable` state that the UI renders as an honest "Connect Apple Health" CTA instead of silently showing nothing/zeroes. Pick real implementation if entitlements allow on-device; otherwise honest gating. State the choice in the tracker.
- `AccountConnector`: clearly mark connectors as demo in the UI (a "Demo data" badge / disabled real-connect button) until real OAuth exists, so the app never implies a live Gmail/Calendar/Slack link. Keep the demo path for simulator.

### 2.4 Network resilience (pillar 4)
- Extract a reusable retry/backoff helper (generalize `MuapiClient.sendWithRetry`) into a shared `HTTPClient`/`NetworkRetry` utility with injectable transport for tests. Apply to `OpenFDAService` and `OpenFoodFactsService` (retry on network/5xx/429) and add a lightweight response cache (in-memory + optional disk, keyed by request) for read-only lookups.
- Fix `CloudSyncService` default: no `localhost:3000` in shipping config — require the Info.plist value and **disable cloud sync with a logged warning** when it's absent/local in a release build, rather than silently no-op'ing.
- Begin consolidating hand-rolled `JSONSerialization` parsing in `AIService` toward `Codable` response types (incremental, one feature at a time), reducing brittleness. Do not merge the two AI stacks wholesale in one step.

### 2.5 Regression guards (pillar 5)
- Add `.github/workflows/ci.yml` running `xcodebuild test` on the iOS simulator for `PulseLoopTests` (and UI tests once they exist). Cache derived data where practical.
- Add a `PulseLoopUITests` target with smoke tests for: fresh-install onboarding shows the empty Install Catalog, installing a module makes it appear, opening Coach presents the chatbox. (If adding a new Xcode target via pbxproj is too risky for one iteration, add XCTest-level integration tests in `PulseLoopTests` that exercise the same flows headlessly, and note the UI-target follow-up.)
- Add localization scaffolding: create a `Localizable.xcstrings` (or `.strings`) and migrate a **small, representative** set of user-facing strings (e.g. the onboarding/empty-state copy) to `String(localized:)`, establishing the pattern without boiling the ocean. Standardize accessibility labels on the highest-traffic views first (Home, RootViews/tab bar, Coach, Install Catalog).

---

## 3. Roadmap (ordered; each item is one safe, shippable iteration)

**Phase A — Protect user data (highest priority, do first)**
- A1. Add `AppLog` logging facade (`os.Logger`, subsystem + categories). Build green. No behavior change.
- A2. Add `ModelContext.saveOrLog(area:)` safe-save helper + `PersistenceError`; migrate the top ~5 highest-value `try? context.save()` sites (Coach view model, `SubAppPersistence`, repositories) to it. Tests for the helper.
- A3. Introduce `VersionedSchema` (`SchemaV1` = current models) + identity `SchemaMigrationPlan`; wire into `ModelContainerFactory` (both on-disk and `inMemory`). Verify existing store loads + tests pass.
- A4. Replace the launch `fatalError` with a graceful recovery screen (retry / reset) that logs via `AppLog`. Keep test path intact.

**Phase B — Make failures visible**
- B1. Sweep remaining high-value `try?`/`try? save` in persistence + capture + ring sync to `do/catch` + `AppLog`; comment intentionally-ignored ones. No UI regressions.
- B2. Add user-facing error surfacing for the most critical write paths (a small reusable error toast/banner in the design system) wired to Coach + notes/tasks saves.

**Phase C — Honest stubs**
- C1. `HealthKitIngestion`: decide + implement real `HKHealthStore` reads (HR/HRV/SpO2/steps/sleep) OR an explicit `HealthDataSource` state + "Connect Apple Health" honest gating in the UI. Record the decision in the tracker.
- C2. `AccountConnector`: mark connectors as demo in the UI (badge + disabled real-connect) so no live integration is implied; keep simulator demo path.

**Phase D — Harden network edges**
- D1. Extract shared retry/backoff (`NetworkRetry`) from `MuapiClient` pattern with injectable transport; unit test it.
- D2. Apply retry + lightweight cache to `OpenFDAService` and `OpenFoodFactsService`.
- D3. Fix `CloudSyncService` production default (no `localhost:3000` in release; disable + log when unset).
- D4. Migrate one `AIService` feature from `JSONSerialization` to `Codable` as the template; note the remaining ones as follow-ups.

**Phase E — Guard against regressions**
- E1. Add `.github/workflows/ci.yml` running `xcodebuild test` (PulseLoopTests) on a pinned simulator.
- E2. Add smoke tests for fresh-install onboarding → empty catalog → install module → Coach presents (UI target if feasible, else headless integration tests in PulseLoopTests + UI-target follow-up).
- E3. Localization scaffolding (`Localizable.xcstrings`) + migrate onboarding/empty-state strings to `String(localized:)` as the pattern.
- E4. Accessibility pass on Home, RootViews tab bar, Coach, Install Catalog (labels/hints/traits, 44pt targets, Dynamic Type check).

**Phase F — Structural cleanup (only after A–E)**
- F1. Move large knowledge blobs (`PeptideKnowledge`/`SupplementKnowledge`/`MedicationKnowledge`) to bundled JSON loaded at runtime; keep the same public API. F2. Decompose one monolith view (start with `TrackerView`) into smaller subviews/files without behavior change.

---

## 4. THE LOOP PROMPT (paste this each session)

```
You are continuing a long-running project: hardening the PulseLoop iOS app from a
strong prototype into a shippable, resilient product WITHOUT regressing any feature.
Your single source of truth is docs/HARDENING_LOOP_PROMPT.md (mission §0, code anchors
§1, architecture target §2, roadmap §3, guardrails §5) and the live tracker
docs/HARDENING_PROGRESS.md.

Do EXACTLY ONE iteration, then stop. Follow this loop:

1. ORIENT. Read docs/HARDENING_LOOP_PROMPT.md and docs/HARDENING_PROGRESS.md. If
   HARDENING_PROGRESS.md does not exist, create it from the §3 roadmap with every item
   set to "pending", then treat iteration A1 as current.

2. SELECT. Pick the single highest-priority "pending" iteration (top-to-bottom in §3).
   Restate it in one sentence. If it is too big for one safe, shippable step, split it:
   do the first sub-step now and add the remainder as new pending items.

3. PLAN. Write a short todo list for this iteration only. Verify the exact real files
   from §1 by reading them — never invent file paths, type names, or model fields.
   Confirm the actual ModelContainerFactory setup, @Model list, and the real signatures
   you will touch before editing.

4. IMPLEMENT. Make the change, reusing existing patterns and keeping behavior identical
   on the happy path:
   - Logging: route through the AppLog facade (os.Logger). Never add print().
   - Persistence: never introduce a new try? context.save(); use the saveOrLog helper.
     SwiftData changes are additive only (optional/defaulted fields, tolerant decoders)
     and covered by the versioned schema/migration plan. Never drop user data.
   - Network: reuse the shared retry/backoff + cache utility; inject transport so it
     stays testable. No secrets in source — Keychain only.
   - Stubs: if a feature is not real, the UI must say so honestly (no implied live data).
   - Design system is law: PulseColors/PulseFont/PulseRadius/PulseLayout + components
     from AppTheme.swift + Components.swift, .cursor/rules/design-system.mdc. SF Symbols
     only, no emoji in UI, primary buttons black.
   - Localization/accessibility work follows §2.5 (xcstrings + String(localized:),
     labels/hints/traits, 44pt targets, Dynamic Type).

5. VERIFY. Build and resolve errors before finishing:
   xcodebuild -project PulseLoop.xcodeproj -scheme PulseLoop \
     -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
   Then run the test suite (at least the affected tests; full suite when persistence or
   schema changed):
   xcodebuild -project PulseLoop.xcodeproj -scheme PulseLoop \
     -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
   Run ReadLints on edited files. Add/adjust tests where §3 calls for them. The app MUST
   build AND existing tests MUST pass at the end of the iteration.

6. RECORD. Update docs/HARDENING_PROGRESS.md: mark this iteration done with a 1–3 line
   summary (what changed + which files + any new types/helpers), list follow-ups you
   spun off, and clearly name the NEXT pending iteration.

7. STOP. Post a concise summary: what you did, build + test status, the next iteration.
   Do not start the next iteration. Do not create a git commit unless I ask.

Rules of engagement:
- Keep the build green AND tests green; never leave a broken state.
- No behavior regressions — hardening adds safety/logging/recovery around features, it
  does not change their happy-path behavior.
- Prefer small, reversible, additive steps so old paths keep working.
- A stub that looks real is a bug: either implement it or gate it honestly in the UI.
- If a decision has real product trade-offs (real HealthKit vs honest gating, cache TTL,
  what to localize first), state your default, proceed, and note it in the tracker
  rather than blocking.
- If you find the roadmap is wrong, propose the fix in the tracker and adjust, but still
  complete one concrete shippable step this iteration.
```

---

## 5. Guardrails (referenced by the loop — the hard rules)

- **Build + tests green every iteration.** End state compiles, runs, and passes the existing ~160 tests; Xcode build + test + ReadLints are the gate.
- **Never lose user data.** SwiftData changes are additive/lightweight (optional/defaulted fields, tolerant decoders) and covered by the versioned schema + migration plan. No `try? context.save()` — use the safe-save helper. No destructive migrations.
- **No silent failures.** Anything that matters (saves, network, decode) logs via `AppLog`; truly ignorable best-effort `try?` must be commented as intentional. No `print()`.
- **No stub masquerading as real.** A not-yet-implemented integration must present an honest UI state (Not connected / Demo data / Coming soon). Never render fake data as if live.
- **No behavior regressions.** Hardening wraps features in safety; it does not change their happy-path behavior or visuals.
- **Network resilience is shared + testable.** Retry/backoff/cache go through one injectable utility (modeled on `MuapiClient`); transports are mockable. No per-service ad-hoc retry copies.
- **Security.** No API keys/secrets in source; Keychain only. Don't spread the legacy plaintext key handling.
- **Design system is law.** `PulseColors`/`PulseFont`/`PulseRadius`/`PulseLayout` + components from `App/AppTheme.swift` + `DesignSystem/Components.swift`; obey `.cursor/rules/design-system.mdc`. SF Symbols only (no emoji in rendered UI). Primary buttons black, accent sparingly.
- **Accessibility & i18n forward-only.** New/changed surfaces get VoiceOver labels, 44pt targets, Dynamic Type support; new user-facing strings use `String(localized:)`.
- **One iteration at a time.** A single shippable step, then stop — keeping the project reviewable.

