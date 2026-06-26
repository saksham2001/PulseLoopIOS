# Delivery Loop — Progress Tracker

> Live status for the "make PulseLoop deliverable" effort. Source of truth for the roadmap
> is `docs/DELIVERY_LOOP_PROMPT.md` (mission §0, anchors §1, target §2, roadmap §3,
> guardrails §5). Each loop iteration updates this file: mark the iteration done, summarize
> the change + touched files, list follow-ups, and name the next pending iteration.

**Status legend:** `pending` · `in-progress` · `done` · `blocked`

**Decided scope:** Paid App Store launch (server proxy + server credits + StoreKit
validation + Clerk accounts) · web phases after backend · Tauri desktop target.

**Current iteration:** H3 (Phases A–G + H1–H2 complete)
**Last completed:** Provider fix — migrated the web AI backend (both Coach routes) from OpenAI to **OpenRouter**, matching the iOS provider; added server-side Responses⇄chat-completions translation + a `coach_sessions` store

> ⚠️ **SECURITY — action needed from you:** Phase A4 found a **live OpenRouter API key
> committed in `PulseLoop/Info.plist`** (and therefore in git history + every shipped
> binary). It has been replaced with the `REPLACE_WITH_YOUR_OPENROUTER_KEY` placeholder.
> **You must REVOKE/rotate that key in your OpenRouter dashboard** — it must be considered
> compromised. It also remains in git history; scrub it (e.g. `git filter-repo`) before the
> repo is shared publicly.

---

## Phase A — Ship hygiene & truth

| ID | Iteration | Status |
|----|-----------|--------|
| A1 | `#if DEBUG`-gate dev-only surfaces (DebugView, debug repos, `-seedDemo`, "Reseed demo data", debug Settings rows). | done |
| A2 | Fix CI to the correct toolchain (Xcode 26.5+/Swift 6.2+); add a `web/` build+lint job. | done |
| A3 | Fix the Sleep "last recorded vs last night" bug; add a test. | done |
| A4 | Replace `web/README.md` boilerplate; audit `Info.plist` usage strings + capabilities. | done |

## Phase B — Provider strategy & AI consolidation

| ID | Iteration | Status |
|----|-----------|--------|
| B1 | Decide + gate the shipping provider matrix (non-shipping modes hidden; `offlineStub` dev-only). | done |
| B2 | Route legacy `AIService` through the metered path, or retire onto the Coach transport. | done |

## Phase C — Real backend: AI proxy

| ID | Iteration | Status |
|----|-----------|--------|
| C1 | Drizzle tables (users, credits balance, credit transactions) + migration. | done |
| C2 | Implement `api/v1/coach/responses` (auth → balance → forward → meter → debit → 402). | done |
| C3 | Wire iOS `backendProxy` end-to-end + "buy credits" deep-link from out-of-credits. | done |

## Phase D — Real billing (StoreKit + server validation)

| ID | Iteration | Status |
|----|-----------|--------|
| D1 | `.storekit` config matching the three product ids; document App Store Connect setup. | done |
| D2 | Server endpoint validates the App Store transaction and grants credits server-side. | done |

## Phase E — Legal & data rights

| ID | Iteration | Status |
|----|-----------|--------|
| E1 | Consent before any cloud upload; privacy policy page on `web/` linked from onboarding/Settings. | done |
| E2 | Data export (local + server) + account/device deletion flows in Settings. | done |
| E3 | Clerk-backed account on iOS reconciled with the device pairing link. | done |

## Phase F — Quality & observability

| ID | Iteration | Status |
|----|-----------|--------|
| F1 | Crash/error reporting (MetricKit-first or hosted) + opt-in content-free analytics seam. | done |
| F2 | E2E correctness sweep: empty/loading/error/offline states; no force-unwraps on JSON; a11y. | done |
| F3 | UI smoke coverage + release-build checklist (signing, capabilities, metadata). | done |

## Phase G — Web design-system parity

| ID | Iteration | Status |
|----|-----------|--------|
| G1 | Port iOS tokens into `web/` (`globals.css` `@theme` + `tokens.ts`); Newsreader + Hanken; light theme. | done |
| G2 | Shared web component kit mirroring iOS; re-skin existing dashboard/pairing/auth as proof. | done |

## Phase H — Web feature parity (one surface per iteration)

| ID | Iteration | Status |
|----|-----------|--------|
| H1 | Coach chat surface (`/coach`) on the shared backend via session-authed `/api/v1/coach/web`. | done |
| H2 | Today surface (`/today`): headline metric summary cards (latest/today/last-night) on `/api/metrics`. | done |
| H3..Hn | Tracker → Sleep/Activity/Vitals → Notes → Tasks → Journal → Mood/Stress/Meditation → Sub-apps/registry → Credits, each on the shared backend. | pending |

## Phase I — Desktop-portability hardening (Tauri)

| ID | Iteration | Status |
|----|-----------|--------|
| I1 | Extract platform-agnostic core (`web/src/core/`): types, API client, state, sub-app runtime. | pending |
| I2 | Capability interfaces (storage, notifications, file export, external links) with web impls. | pending |
| I3 | Document the Tauri wrapper plan + portability checklist; verify configurable API base URL. | pending |

---

## Iteration Log

_(newest first)_

### Provider fix — web AI backend on OpenRouter (done)

The web AI routes were calling **OpenAI** (`api.openai.com/v1/responses`) with an `OPENAI_API_KEY`. The
whole product uses **OpenRouter**, so both routes were migrated to the same provider the iOS app uses.

- **New `web/src/lib/openrouter.ts`:** TypeScript port of the app's `OpenRouterResponsesClient` —
  translates the OpenAI **Responses**-shaped body the iOS orchestrator builds (`{model, input, tools,
  text.format, previous_response_id}`) into OpenRouter **chat-completions** (`{model, messages, tools,
  response_format}`), and the chat-completions reply back into the Responses shape (`{id, output[], usage}`)
  that `OpenAIResponse.parse` reads. Carries the same provider quirks (no strict schema + `tools` together;
  one-time `coach_response` JSON nudge; `developer`→`system` role map; deferred `tool_calls`). Endpoint
  `openrouter.ai/api/v1/chat/completions`, `X-Title` header, default model `google/gemini-2.5-flash`
  (= iOS `AIModel.smart`).
- **New `coach_sessions` table + `web/src/lib/coach-session.ts`:** OpenRouter is stateless and has no
  `previous_response_id`, but the iOS multi-round tool loop relies on it (later rounds send only the new tool
  outputs). The proxy now persists the running chat history + deferred `tool_calls` keyed on the response id
  it mints, and resumes on the next turn's `previous_response_id`. Migration `drizzle/0001_warm_ozymandias.sql`.
- **`/api/v1/coach/responses` (device proxy):** Rewritten to load session → translate → POST OpenRouter →
  parse → persist new session → debit `coach_turn` (idempotent on the minted response id) → return the
  Responses-shaped payload + `pulseloop_credits.balance`. Uses `OPENROUTER_API_KEY`.
- **`/api/v1/coach/web` (web chat):** Now posts chat-completions to OpenRouter directly (text-only),
  `OPENROUTER_API_KEY` + optional `OPENROUTER_COACH_MODEL`, debiting on `prompt/completion_tokens`.
- **Docs/comments:** README API + env tables now say `OPENROUTER_API_KEY`/`OPENROUTER_COACH_MODEL`;
  `RELEASE_CHECKLIST.md` updated; `BackendProxyResponsesClient` doc comment de-OpenAI'd (wire contract
  unchanged — it still sends a Responses body; the server does the provider translation). Note: the iOS
  *user-supplied-key* provider modes (`OpenAIResponsesClient`, `OpenAIKeychainStore`, `OpenAITTSEngine`) are
  separate opt-in on-device paths and left as-is.
- **Verification:** `drizzle-kit generate` clean; `next build` + `eslint` clean; no IDE lint diagnostics.

**Touched:** `web/src/lib/openrouter.ts`, `web/src/lib/coach-session.ts`, `web/src/db/schema.ts`,
`web/drizzle/0001_warm_ozymandias.sql` (+ meta), `web/src/app/api/v1/coach/responses/route.ts`,
`web/src/app/api/v1/coach/web/route.ts`, `web/README.md`, `docs/RELEASE_CHECKLIST.md`,
`PulseLoop/Coach/OpenAI/BackendProxyResponsesClient.swift`.

**Follow-up:** Apply the new migration in the deployment DB (`db:push`/`migrate`); set `OPENROUTER_API_KEY`.


### H2 — Web Today surface (done)

The day-at-a-glance surface, mirroring the iOS Today tab on the shared backend.

- **`web/src/app/today/today-panel.tsx`:** Fetches the last 3 days from `/api/metrics` and renders four
  headline metric cards — heart rate + blood oxygen (latest reading w/ timestamp), steps (today's total +
  reading count), and last night's sleep (formatted `Xh Ym`). Each metric is summarized the way it's
  naturally read via a `Stat` strategy (`latest` / `sumToday` / `lastNight`); dots use the health-metric
  token colors. Loading shows skeleton cards; the all-empty case shows a calm "nothing synced yet" prompt.
- **`web/src/app/today/page.tsx`:** Newsreader date label + "Your day so far" title, dashboard back-link,
  `UserButton`, on the shared card kit.
- **Wiring:** `/today` added to the Clerk-protected matcher; dashboard header now has Today + Talk-to-coach
  buttons.
- **Verification:** `next build` + `eslint` clean; no IDE lint diagnostics; `/today` registered.

**Touched:** `web/src/app/today/today-panel.tsx`, `web/src/app/today/page.tsx`,
`web/src/app/dashboard/page.tsx`, `web/src/middleware.ts`.

**Follow-up:** When richer per-metric history/trends land (H3+ Tracker), Today cards can link into detail views.


### H1 — Web Coach chat (done)

First web feature surface, built entirely on the shared backend + the Phase G component kit.

- **Server route `web/src/app/api/v1/coach/web/route.ts`:** Session-authed (Clerk) Coach turn that
  mirrors the device proxy's economics — checks the **server-authoritative credit ledger** before spending
  the OpenAI budget, forwards a Responses request with the server-side `OPENAI_API_KEY`, then debits
  `coach_turn` keyed on the OpenAI response id (idempotent). Returns `{reply, balance}`, `402` with the
  balance when out of credits, and never leaks the key or raw upstream errors. Input is sanitized: message +
  history clamped (`MAX_HISTORY`, `MAX_CHARS`), only `user`/`assistant` roles kept. System prompt ports the
  iOS Coach persona but is honest that live ring data lives on the iPhone (no on-device tool runtime on web).
  Text reply is extracted defensively from the Responses payload (`output_text` or `output[].content[]`).
- **UI `web/src/app/coach/` (`page.tsx` + `coach-chat.tsx`):** Messenger styling straight from the design
  rule — sent = black bubble/white text, received = `fill-subtle`, 18px radius, `fill-subtle` rounded input
  with a circular black send button, typing-dots while awaiting, Enter-to-send / Shift+Enter newline. Shows
  remaining credits and a friendly out-of-credits message pointing to the iPhone app for top-ups.
- **Wiring:** `/coach` added to the Clerk-protected matcher in `middleware.ts`; a "Talk to coach" button added
  to the dashboard header. README API table + env table updated (`/api/v1/coach/web`, `OPENAI_COACH_MODEL`).
- **Verification:** `next build` + `eslint` clean; no IDE lint diagnostics; both new routes registered.

**Touched:** `web/src/app/api/v1/coach/web/route.ts`, `web/src/app/coach/page.tsx`,
`web/src/app/coach/coach-chat.tsx`, `web/src/app/dashboard/page.tsx`, `web/src/middleware.ts`,
`web/README.md`.

**Follow-up:** Later H surfaces (Today/Tracker/Sleep/etc.) reuse this kit + ledger pattern; web Coach can grow
tools/context once a web-readable data path exists. A web credits top-up needs a non-StoreKit purchase path.


### G1+G2 — Web design-system parity (done)

Ported the iOS design system to the web app so the two surfaces share one visual language.

- **Tokens (`web/src/app/globals.css`):** Read every `*.colorset` in `PulseLoop/Assets.xcassets` and
  `PulseFont`/`PulseRadius` from `AppTheme.swift`, converted the sRGB components to hex, and emitted them as
  CSS custom properties under `@theme` (light default, `.dark`/`[data-theme=dark]` override). Surfaces, borders,
  text ramp, accent, semantic + health-metric colors, and radii are now Tailwind utilities (`bg-background`,
  `text-text-primary`, `border-border-hairline`, `text-heart-rate`, `rounded-[14px]`, …).
- **Typography:** Swapped Geist → **Newsreader** (serif titles, `--font-serif`) + **Hanken Grotesk**
  (body/UI, `--font-sans`) in `layout.tsx`, matching the iOS `PulseFont` stack. Switched the app off the
  hardcoded dark `bg-neutral-950` body onto the calm light `canvas`.
- **`web/src/lib/tokens.ts`:** Typed constants (colors per scheme, semantic/health palette, radii, layout,
  type scale) for raw-value needs (charts, inline styles) — annotated as a 1:1 mirror of the iOS source.
- **Component kit (`web/src/components/ui.tsx`):** `PulseCard`, `PulseTitle`, `PulseSectionLabel`,
  `PulseButton` (black-fill primary / outlined secondary / destructive), `PulseLinkButton`, `PulseChip` —
  encoding the design-system rules (hairline cards, 44px buttons, 12–14px radii, uppercase tracked labels).
- **Re-skin:** Landing, dashboard shell, pair-device, metrics panel (charts now use the health-metric token
  per kind + light tooltip), sign-in/up (Clerk `appearance` → black primary, 12px radius, Hanken), and the
  privacy page — all moved off `neutral-*`/`emerald-*` onto the shared tokens.
- **Verification:** `next build` + `eslint` clean; no IDE lint diagnostics.

**Touched:** `web/src/app/globals.css`, `web/src/app/layout.tsx`, `web/src/lib/tokens.ts`,
`web/src/components/ui.tsx`, `web/src/app/page.tsx`, `web/src/app/dashboard/page.tsx`,
`web/src/app/dashboard/pair-device.tsx`, `web/src/app/dashboard/metrics-panel.tsx`,
`web/src/app/privacy/page.tsx`.

**Follow-up:** Dark-mode toggle UI (tokens already support `.dark`); Phase H builds feature surfaces on this kit.


### F3 — Smoke coverage + release checklist (done)
- **Found + fixed 3 release blockers.** The audit (`Info.plist` vs actual API use)
  revealed missing **usage strings** that would crash the app and fail review:
  - `GpsRouteRecorder` calls `requestWhenInUseAuthorization()` +
    `requestAlwaysAuthorization()` with background location, but there were **no**
    `NSLocation*UsageDescription` keys → instant crash on the first workout.
  - `RingBLEClient` instantiates `CBCentralManager`, which on iOS 13+ **requires**
    `NSBluetoothAlwaysUsageDescription` → crash at manager init.
  Added `NSLocationWhenInUseUsageDescription`,
  `NSLocationAlwaysAndWhenInUseUsageDescription`, and
  `NSBluetoothAlwaysUsageDescription` with specific, review-friendly copy.
- **Smoke coverage** extended (`SmokeFlowTests`): cloud-sync refuses upload without
  consent (E1 invariant) and surfaces the consent error; `webKind` mapping is
  stable (`heart_rate`/`spo2`); `DeleteScope` raw values match the wire contract.
- **Release checklist** added (`docs/RELEASE_CHECKLIST.md`): signing/identifiers,
  capabilities/entitlements, the full purpose-string list, secrets (placeholder key
  + server env), build hygiene, on-device functional smoke, and App Store Connect
  metadata (privacy label aligned to `web/privacy`, IAP "Ready to Submit").
- Full suite green: **249 tests, 0 failures**. Files: `PulseLoop/Info.plist`,
  `PulseLoopTests/SmokeFlowTests.swift`, `docs/RELEASE_CHECKLIST.md`.

**Next iteration:** G1 — Port iOS design tokens into `web/` (Phase G kickoff).

### F2 — Correctness sweep (done)
- **Found + fixed a real latent bug.** The full iOS suite had 4 failures
  (`CoachSummaryServiceTests` ×3, `CoachNotificationServiceTests` ×1). Root cause:
  both services resolved the API key via `AIService.shared.currentAPIKey` and
  ignored their **injected** `keyStore`. After A4 (correctly) replaced the committed
  OpenRouter key with a placeholder — which `resolvedAPIKey()` ignores — those tests
  silently fell back to scripted content instead of the stubbed LLM. So the tests
  depended on a bundled secret. Fixed by preferring the injected `keyStore`
  (`(try? keyStore.readKey()).flatMap { $0 } ?? AIService.shared.currentAPIKey`) in
  `CoachSummaryService.generateAndUpsert` and `CoachNotificationService.runDueSlot` —
  this also makes alt-provider key injection work at runtime, not just in tests.
- **JSON robustness audit.** No `try!` / forced JSON casts in the iOS networking or
  decode paths; all `URL(string:)!` uses are compile-time literal endpoints (safe).
  The web AI proxy + new account routes use guarded parsing and return typed
  status codes (401/402/502/503), never force-unwrapping untrusted bodies.
- **New tests** (`PulseLoopTests/PrivacyDataTests.swift`): telemetry routes to an
  injected sink with correct names/params; diagnostics consent persists; local
  export captures profile + measurements and produces a valid JSON file.
- Full suite green: **247 tests, 0 failures** (242 prior + 5 new). Files:
  `PulseLoop/Coach/Summaries/CoachSummaryService.swift`,
  `PulseLoop/Coach/Notifications/CoachNotificationService.swift`,
  `PulseLoopTests/PrivacyDataTests.swift`.

**Next iteration:** F3 — UI smoke coverage + release-build checklist (signing,
capabilities, metadata).

### F1 — MetricKit diagnostics + content-free telemetry seam (done)
- **No third-party SDK.** Crash/hang/CPU/disk diagnostics come from Apple's
  `MetricKit` (`MXMetricManagerSubscriber`), which delivers payloads on-device; we
  log counts via `AppLog`. Usage telemetry is a thin `Telemetry` protocol + global
  `Analytics.track(name, params)` seam whose default `LoggingTelemetry` only logs
  event *names* + low-cardinality non-PII params — a hosted backend can swap in
  behind the same protocol without touching call sites.
- **Opt-in & revocable.** Everything is gated behind `DiagnosticsConsent.isEnabled`
  (off by default, `UserDefaults`). The MetricKit subscriber starts at launch only
  when enabled (`DiagnosticsService.startIfEnabled()` in `PulseLoopApp.init`), and
  flipping the Settings toggle starts/stops it immediately. No consent → no
  collection, no emission.
- **UI.** Added a "Share crash diagnostics & anonymous usage" toggle to the
  Privacy & data section, with a "no health data or personal content" note. Wired a
  couple of content-free events (`export_local`, `account_delete{scope}`) as proof.
- **Privacy policy.** Added a "Diagnostics & analytics" section to `web/privacy`
  describing the opt-in, content-free signals.
- MetricKit conformance is `#if canImport(MetricKit) && !targetEnvironment(simulator)`
  so it compiles for both simulator (Debug) and device (verified via a
  `generic/platform=iOS` **Release** build) — both succeed; web lint+build clean.
- Files: `PulseLoop/Services/DiagnosticsService.swift`, `PulseLoop/PulseLoopApp.swift`,
  `PulseLoop/Views/PrivacyDataSettingsSection.swift`, `web/src/app/privacy/page.tsx`.

**Next iteration:** F2 — E2E correctness sweep (empty/loading/error/offline states;
no force-unwraps on JSON; a11y).

### E3 — Linked-account identity on iOS (done)
- The pairing model already ties a device token to a Clerk-backed account (the code
  is generated inside a signed-in web session), but the phone never learned *which*
  account. This iteration makes that link visible/verifiable on-device — the
  shippable reconciliation step, and the foundation for a future native Clerk sign-in.
- **Server.** Added `GET /api/v1/account/me` (device token): resolves the device's
  owner → returns `{ account: { email, creditBalance }, device: { id, name,
  pairedAt, lastSeenAt } }`.
- **iOS.** `CloudSyncService` gained a `LinkedAccount` struct, a published
  `linkedAccount`, and `refreshLinkedAccount()` (tolerant of transient failures —
  keeps the prior value). `unpair()` clears it.
- **iOS UI.** `CloudSyncSettingsSection`'s paired state now shows "Signed in as
  &lt;email&gt;"; it refreshes on appear (`.task`) and right after a successful connect,
  so the user can confirm they linked the intended account.
- Build + lint clean on both targets (new `ƒ /api/v1/account/me` route). Files:
  `web/src/app/api/v1/account/me/route.ts`, `PulseLoop/Services/CloudSyncService.swift`,
  `PulseLoop/Views/CloudSyncSettingsSection.swift`, `web/README.md`.

**Next iteration:** F1 — Phase F (Quality & observability) kickoff.

### E2 — Data export + account/device deletion (done)
- **Server.** Added two device-token endpoints:
  - `GET /api/v1/account/export` returns one JSON document with everything the
    server holds for the owner: paired devices, all metric samples, the credit
    balance, and the full credit ledger — the data-portability artifact.
  - `POST /api/v1/account/delete` with `{scope}`: `"device"` (default) nulls just
    this device's token (other devices/data kept); `"account"` deletes the user's
    metric samples, credit ledger, credit balance, and device rows (right to
    erasure). The Clerk-backed `users` row survives so the web login still works.
- **iOS service.** `CloudSyncService` gained `exportServerData()` (GETs the export
  bytes), a `DeleteScope` enum, and `deleteServerData(scope:)` (POSTs delete, then
  unpairs locally so the app reflects the revoked/erased state).
- **iOS local export.** New `LocalDataExport` serializes the on-device SwiftData
  (profile, goal, measurements, sleep, daily activity, sessions) to a pretty JSON
  file in tmp — works even if the user never connected to the cloud.
- **iOS UI.** New `PrivacyDataSettingsSection` (added to `SettingsView`): "Export
  my data (this device)" always available via a share sheet; when paired, "Download
  my web data", "Disconnect this device", and a destructive "Delete all my web data"
  appear. Both deletes are confirmation-alert gated; reuses the existing `ShareSheet`.
- Build + lint clean on both targets (iOS iPhone 17 / iOS 26.5; web lint+build with
  the two new `ƒ` routes). Files: `web/src/app/api/v1/account/{export,delete}/route.ts`,
  `PulseLoop/Services/CloudSyncService.swift`, `PulseLoop/Services/LocalDataExport.swift`,
  `PulseLoop/Views/PrivacyDataSettingsSection.swift`, `PulseLoop/Views/SettingsView.swift`,
  `web/README.md`.

**Next iteration:** E3 — Clerk-backed account on iOS reconciled with the device
pairing link.

### E1 — Cloud-sync consent + privacy policy (done)
- Added `hasCloudConsent` (persisted in `UserDefaults`) + `SyncError.consentRequired`
  to `CloudSyncService`; `pair()` and `sync()` now hard-guard on it (can't be bypassed
  by calling the service directly), and `unpair()` revokes consent so reconnecting
  requires a fresh opt-in.
- `CloudSyncSettingsSection` gained a consent toggle + privacy-policy link; the
  "Connect" button is disabled until consent is granted, and the paired state keeps a
  standing privacy-policy link.
- Added `web/src/app/privacy/page.tsx` (public route — only `/dashboard` is Clerk-gated)
  covering what's collected, how it's used, consent/control, storage/sharing, and
  user rights; `CloudSyncService.privacyPolicyURL` points at it.
- Build + lint clean on both targets. Files: `PulseLoop/Services/CloudSyncService.swift`,
  `PulseLoop/Views/CloudSyncSettingsSection.swift`, `web/src/app/privacy/page.tsx`.

**Next iteration:** E2 — Data export (local + server) + account/device deletion.

### D2 — App Store validation + server-side grant (done)
- Added `web/src/lib/appstore.ts`: wraps Apple's `@apple/app-store-server-library`
  `SignedDataVerifier` to verify a signed JWS transaction. Fully env-configured
  (`APP_STORE_BUNDLE_ID`, `APP_STORE_APPLE_APP_ID`, `APP_STORE_ENVIRONMENT`,
  `APP_STORE_ROOT_CERTS`); when unconfigured it reports `unconfigured` so credits are never
  granted on unverified data.
- Added `POST /api/v1/credits/validate`: device-auth → verify JWS with Apple → map product id →
  credits (`CREDITS_BY_PRODUCT_ID`, mirrors iOS `CreditStore`) → `grantCredit` idempotent on
  the Apple transaction id (`appstore:<txnId>`) → return authoritative `{granted, balance}`.
  `503` when verification env isn't set.
- iOS `CreditStore.handle(verification:)` now prefers server validation: posts
  `verification.jwsRepresentation` to the proxy, adopts the returned authoritative balance, and
  only falls back to a local grant when the backend isn't configured (sandbox/TestFlight).
- Added the `@apple/app-store-server-library` dependency. Web lint + build pass (route in the
  manifest); iOS build passes; no new lints.
- Files: `web/src/lib/appstore.ts`, `web/src/app/api/v1/credits/validate/route.ts`,
  `web/src/lib/credits.ts`, `web/package.json`, `PulseLoop/Services/CreditStore.swift`,
  `web/README.md`.
- ⚠️ **Needs from you to go live:** the `APP_STORE_*` env vars incl. the Apple root CA DER
  file(s), and the real consumable products in App Store Connect.

**Phase D (real billing) complete.** The full money path now exists in code: metered proxy +
server-authoritative ledger + StoreKit purchases validated server-side. Going *live* needs your
deployment + Apple/OpenAI credentials (all clearly marked above).

**Next iteration:** E1 — consent before any cloud upload + a privacy-policy page on `web/`
linked from onboarding/Settings. (Implementable without secrets.)

### D1 — StoreKit config + billing docs (done)
- Added `PulseLoop.storekit` (local StoreKit 2 configuration) with the three **consumable**
  credit packs matching `CreditStore.creditsByProductID`: `com.pulseloop.credits.100` ($0.99),
  `.500` ($3.99), `.1200` ($7.99). Lets purchases work in the Simulator/dev without App Store
  Connect; validated as well-formed JSON.
- Added `docs/BILLING_SETUP.md`: the product table + the rule that credit amounts are decided
  by the app's id→credits map (not StoreKit), how to enable the `.storekit` config in the Run
  scheme, App Store Connect product setup steps, and the planned D2 server-validation flow
  (verify JWS, grant with the transaction id as idempotency key, sync authoritative balance).
- Files: `PulseLoop.storekit`, `docs/BILLING_SETUP.md`.
- ⚠️ **Needs from you:** point the Run scheme's *StoreKit Configuration* at `PulseLoop.storekit`
  for local testing, and create the three consumable products in App Store Connect for release.

**Next iteration:** D2 — web endpoint that validates an App Store transaction and grants credits
server-side (idempotent on the transaction id) so the balance can't be forged. ⚠️ Going live
needs your Apple in-app-purchase / App Store Server API credentials.

### C3 — iOS backend-proxy path wired end-to-end (done)
- `CoachViewModel.makeClient` now honors `providerMode == .backendProxy`: when a valid
  `backendProxyURL` + paired device token exist it builds `BackendProxyResponsesClient`
  (server holds the OpenAI key, server-authoritative credits); otherwise it falls through to
  the injected `clientFactory` (default OpenRouter / test stubs). Added an injectable
  `deviceTokenProvider` (defaults to `CloudSyncKeychainStore`).
- Fixed double-counting: in proxy mode the VM skips local metering since the server already
  debited and synced the balance via `pulseloop_credits`.
- `CoachFeatureFlags.coachEnabled`/`statusLine` now treat proxy mode correctly — the coach is
  enabled with a configured proxy URL and **no** on-device key (key lives on the server);
  BYO-key mode still requires a key; the master switch still gates everything.
- Out-of-credits now opens the existing `CreditsView` paywall as a sheet (VM `outOfCredits`
  flag → `CoachView` `.onChange` presents it), giving an in-place "buy credits" path.
- Tests: added `CoachProviderMatrixTests` cases for proxy-enables-without-key,
  proxy-disabled-when-URL-missing, BYO-requires-key, and master-off-disables-all. Build +
  tests pass; no new lints.
- Files: `PulseLoop/Coach/ViewModels/CoachViewModel.swift`,
  `PulseLoop/Coach/Config/CoachFeatureFlags.swift`, `PulseLoop/Views/CoachView.swift`,
  `PulseLoopTests/CoachTests.swift`.

**Phase C (money path: server proxy + enforcement) complete.** ⚠️ To run live you still need:
the web app deployed with `OPENAI_API_KEY` set, the credit tables applied (`db:push`), and a
build that sets `CoachSettings.backendProxyURL` to your deployment (e.g. via a build config or
a Settings field — a provider/URL field can be added in a later UI iteration).

**Next iteration:** D1 — add a `.storekit` configuration matching the three credit-pack product
ids in `CreditStore`, and document the App Store Connect product setup. ⚠️ Creating the real
products in App Store Connect needs your developer account.

### C2 — AI proxy route (done)
- Added `web/src/app/api/v1/coach/responses/route.ts` implementing the exact iOS
  `BackendProxyResponsesClient` contract: device-token auth (`deviceFromRequest`) → check
  server balance → **402 + `pulseloop_credits.balance`** when out → forward the verbatim
  Responses body to OpenAI with the server-side `OPENAI_API_KEY` → debit `coach_turn` recording
  real token usage (idempotent on the OpenAI response id) → return the verbatim OpenAI JSON
  augmented with the authoritative `pulseloop_credits.balance`.
- Security: OpenAI key only in server env; credits enforced before spend so a client can't
  exceed its balance; upstream errors passed through by status without leaking the key.
- Files: `web/src/app/api/v1/coach/responses/route.ts`, `web/README.md`. Lint + build pass;
  the route shows in the Next build manifest.
- ⚠️ **Needs from you to run live:** set `OPENAI_API_KEY` in the deployment env, and apply the
  C1 schema (`db:push`). Auth decision (documented in the route): the proxy authenticates with
  the existing **device token**; C3 wires the iOS side to send it.

**Next iteration:** C3 — wire iOS `backendProxy` mode end-to-end: have `CoachViewModel`/
`CoachFeatureFlags` honor `providerMode == .backendProxy` (construct `BackendProxyResponsesClient`
with `backendProxyURL` + the device token), confirm balance sync + 402 handling, and add a
"buy credits" deep-link from the out-of-credits state.

### C1 — server credits schema + migration + helper (done)
- Added `credit_balances` (one row/user, source of truth synced to iOS) and
  `credit_transactions` (immutable ledger; `delta`, `balanceAfter`, `kind`, token counts,
  idempotency `referenceId` unique) to `web/src/db/schema.ts` + exported types.
- Generated the Drizzle migration `web/drizzle/0000_puzzling_lyja.sql` (baseline incl. all 5
  tables) via `db:generate`.
- Added `web/src/lib/credits.ts`: `getBalance`, `applyCredit` (atomic balance `UPDATE` with an
  insufficient-funds guard + ledger insert, idempotent on `referenceId`), `debitUsage`,
  `grantCredit`. Built for the Neon **HTTP** driver (no interactive txns) — uses an atomic
  guarded update + a unique-constraint dedupe.
- Files: `web/src/db/schema.ts`, `web/drizzle/*`, `web/src/lib/credits.ts`, `web/README.md`.
  Web lint + build pass.
- ⚠️ **Apply step for you:** run `npm run db:push` against the live Neon DB to create the two
  new tables (the baseline migration would re-create existing tables; push diffs and adds only
  what's missing). Documented in `web/README.md`.

**Next iteration:** C2 — implement `POST /api/v1/coach/responses` (auth → balance check →
forward to OpenAI with the server key → meter tokens → debit → return body +
`pulseloop_credits.balance`; `402` when out). Needs a server `OPENAI_API_KEY` to run live; the
route + wiring will be built and verified against the build.

### B2 — meter the legacy AIService (done)
- Centralized metering at `AIService`'s three network entry points so no AI call is
  billing-blind: `complete(...)` and `stream(...)` gained a `usageKind: AIUsageKind = .other`
  parameter and now meter on success; `analyzeFoodImage` meters as `.imageAnalysis`.
- Added `decodeUsage` (parses `usage.prompt_tokens`/`completion_tokens` from chat responses)
  plus `meter`/`meterStream` helpers that record into `CreditsLedger.shared` with real token
  counts when available. Streaming requests now send `stream_options.include_usage` so the
  final chunk's usage is captured.
- Files: `PulseLoop/Services/AIService.swift`. Build + ledger/provider tests pass.
- Note: per-feature `usageKind` tagging (notes/inbox/etc. currently bill as `.other`) can be
  refined later; the billing-blind gap is closed. When the metered proxy lands (Phase C), the
  server becomes authoritative and these calls route through it.

**Phase B (provider strategy & AI consolidation) complete.**

**Next iteration:** C1 — Drizzle tables (users, credits balance, credit transactions) +
migration. ⚠️ Phase C needs your inputs to go fully live: a deployed backend URL, a
server-side `OPENAI_API_KEY`, and the Neon `DATABASE_URL`. The code/migrations will be built;
applying them to a real database + deploying is the part that needs your credentials.

### B1 — provider matrix defined + gated (done)
- Made `CoachProviderMode` the single source of truth for the shipping matrix: added
  `isShippable` (`userOpenAIKey` + `backendProxy` = shipping; `offlineStub` = dev/test;
  `bedrock` = experimental) and `selectableModes` — which returns only shippable modes in
  release and all modes in DEBUG. Any future provider picker MUST iterate `selectableModes`,
  never `allCases`, so a release UI can never offer an unsupported path.
- Added `CoachProviderMatrixTests` (2 tests) asserting the matrix + the release-vs-DEBUG
  gating. Both pass.
- Files: `PulseLoop/Coach/Config/CoachSettings.swift`, `PulseLoopTests/CoachTests.swift`.
- **Findings to carry into Phase C:** the runtime currently ignores `providerMode` entirely —
  `CoachViewModel.makeClient` always uses the injected `clientFactory` (default
  `OpenRouterResponsesClient`), and `CoachFeatureFlags.coachEnabled` gates purely on the master
  switch + an OpenRouter key. The `backendProxy`/`bedrock` clients exist but are never selected.
  Phase C must wire `makeClient`/`CoachFeatureFlags` to honor `providerMode` (proxy path) using
  `selectableModes`. No provider-mode picker is currently shown in Settings — one will be added
  with Phase C/D.

**Next iteration:** B2 — route legacy `AIService` through the metered path, or retire it onto
the Coach transport (no billing-blind AI in a paid build).

### A4 — web README + Info.plist audit (done)
- **Security:** `PulseLoop/Info.plist` contained a **live OpenRouter API key**. Replaced it
  with the `REPLACE_WITH_YOUR_OPENROUTER_KEY` placeholder — which `AIService.resolvedAPIKey()`
  already treats as "no key", so BYO-key (Keychain) + env-var paths are unaffected and AI fails
  gracefully until a real key is supplied. **Owner must revoke/rotate the leaked key and scrub
  git history.**
- **Usage strings:** audited. Camera/Microphone/Speech/HealthShare/HealthUpdate live in
  `Info.plist`; Bluetooth (`NSBluetoothAlways`/`NSBluetoothPeripheral`) + Location
  (`NSLocationWhenInUse`/`NSLocationAlwaysAndWhenInUse`) are set via `INFOPLIST_KEY_*` in both
  Debug+Release build settings — all present. Background modes (location, bluetooth-central,
  fetch, processing) + `BGTaskSchedulerPermittedIdentifiers` are consistent with usage.
- Replaced `web/README.md` create-next-app boilerplate with a real backend README (stack, the
  4 live API routes + the 2 planned ones, env vars, Drizzle/Neon commands, scripts, layout,
  deploy, design-system/portability plan).
- Files: `PulseLoop/Info.plist`, `web/README.md`. iOS build still succeeds.
- Follow-ups (polish, not blocking): Bluetooth/Location usage strings say "SMART_RING" —
  replace with the real product name before submission. Consider moving `PULSELOOP_WEB_URL`
  out of the committed Info.plist into a per-environment config.

**Phase A (ship hygiene & truth) complete.** Next iteration: B1 — decide + gate the shipping
provider matrix (non-shipping `CoachProviderMode`s hidden; `offlineStub` dev-only).

### A3 — Sleep "last recorded vs last night" (done)
- The bug was already fixed in the data layer: `SleepService.sleepRange(.day)` anchors on
  `dayReferenceNight` (flips yesterday→today at 4 AM) and `latestSleep` gates on a 1-day
  staleness cutoff, so a stale night can no longer masquerade as last night. `SleepView`'s
  day view consumes that day-anchored range.
- Added a focused regression test asserting the exact README symptom from the view's angle:
  with both a 5-day-old night and last night present, the Day range surfaces last night only
  (`testDayRangeShowsLastNightNotStaleRecord`). All 10 `SleepServiceTests` pass.
- Updated `README.md`: moved the entry out of "Known bugs" into a "Fixed" note explaining the
  day-anchor behavior + pointing at the test.
- Files: `PulseLoopTests/SleepServiceTests.swift`, `README.md`.

**Next iteration:** A4 — Replace `web/README.md` boilerplate; audit `Info.plist` usage
strings + capabilities.

### A2 — CI on the correct toolchain + web job (done)
- Rewrote `.github/workflows/ci.yml`: the iOS job now runs on `macos-26` and selects the
  highest installed `Xcode_26*.app` (macos-15/Xcode 16 cannot build the voice stack —
  Swift 6.2+ required). It resolves an available iOS 26 iPhone simulator by name (with a
  fallback) instead of hard-coding iPhone 16 Pro, then `clean test`.
- Added a separate `web` job (ubuntu): `npm ci` → `npm run lint` → `npm run build` with
  placeholder Clerk/DATABASE_URL env so the build doesn't fail on missing secrets.
- Verified locally: `npm run lint` ✓ and `npm run build` ✓ (with placeholder env);
  iOS app builds under Xcode 26.5. File: `.github/workflows/ci.yml`.
- Follow-up: Next.js 16 warns `middleware` is deprecated in favor of `proxy`
  (`web/src/middleware.ts`) — builds fine today; migrate during the web phases (G/H).

**Next iteration:** A3 — Fix the Sleep "last recorded vs last night" bug; add a test.

### A1 — DEBUG-gate dev-only surfaces (done)
- Wrapped the `-seedDemo`/`seedDemo` demo-data load in `RootViews.swift` `.task` in
  `#if DEBUG` (exercise-catalog content seeding stays unconditional).
- DEBUG-gated the "Debug" + "Component gallery" buttons under Settings → Tools, and the
  entire demo-data "Data" section ("Clear demo data" / "Reseed demo data") in `SettingsView.swift`.
  Shippable user tools (Sub-App Builder/Store/Credits/Module updates) remain in release.
- Files: `PulseLoop/Views/RootViews.swift`, `PulseLoop/Views/SettingsView.swift`.
- Verified: Debug AND Release builds succeed on iPhone 17 / iOS 26.5 (Xcode 26.5). No lints.
- Note: `AppRoute.debug`/`.componentGallery` enum cases + `DebugView`/`SeedData` remain (used
  only from DEBUG paths now); left in place since they're harmless and useful in dev.

**Next iteration:** A2 — Fix CI to the correct toolchain (Xcode 26.5+/Swift 6.2+); add a
`web/` build+lint job.
