# PulseLoop → Deliverable, Production-Shippable App — Loop Prompt

> **How to use this file.** Paste the section titled **"THE LOOP PROMPT"** (§4) into
> Claude (Cursor agent) as a single message at the start of each working session.
> Claude does EXACTLY ONE iteration, updates the live tracker `docs/DELIVERY_PROGRESS.md`,
> and stops. Re-run to advance. Everything else (Context, Architecture, Roadmap,
> Guardrails) is the reference the prompt points Claude at — keep it in the repo.
>
> This loop is written from the combined perspective of a senior **frontend (iOS/SwiftUI
> + web)**, **backend (Next.js/serverless)**, and **AI** engineer. Its single job: take a
> feature-complete-but-not-deliverable codebase and make it a real, shippable product —
> fix what's broken, remove what shouldn't ship, add what's missing.
>
> **Decided scope (do not re-litigate):** Paid App Store launch (full server AI proxy +
> server-authoritative credits + StoreKit receipt validation + real accounts). Web phases
> come AFTER the backend work (parity rides the shared API). Desktop wrapper target is
> **Tauri**.

---

## 0. North-Star Vision (the fixed mission — never changes between iterations)

Turn PulseLoop from "all feature roadmaps marked done" into **a product you can actually
ship to the App Store and charge money for**, plus a **web app that is a true peer of the
iOS app**, without security holes, review rejections, or paths that silently don't work.
Deliverable pillars:

1. **The money path is real and abuse-proof.** AI usage is metered AND enforced
   server-side; credit purchases are real StoreKit products validated against a backend
   receipt check; a BYO-key user and a paying user are both first-class, and neither can
   spend credits they didn't buy.
2. **The product is App-Store-legal for a health app.** Privacy policy, explicit consent
   before any cloud upload, on-device-first defaults, data export, and account deletion
   all exist and work. No secrets in the binary.
3. **Every shipped path actually works.** No dead endpoints, no stubbed providers
   presented as live, no demo-seed leaking into production, no toolchain/CI lie. Every
   route has real empty/loading/error/offline states; crashes are reported; the build is
   green on the correct toolchain.
4. **The web app is a true peer of the iOS app — same look, same features, portable.** The
   Next.js `web/` app adopts the **exact PulseLoop design system** (iOS
   `PulseColors`/`PulseFont`/`PulseRadius`/`PulseLayout` + `.cursor/rules/design-system.mdc`),
   reaches **feature parity** with iOS (not a read-only dashboard), and is architected so
   it can later be wrapped as a **Tauri Windows/macOS desktop app** with minimal change.

**Non-negotiables across every iteration:**
- The app must **always build and run** at the end of each iteration on the **correct
  toolchain** (Xcode 26.5+/Swift 6.2+, since the voice stack requires it). The `web/`
  backend must `npm run build` clean when touched.
- **No secrets in source.** Keys live in Keychain (iOS) / server env (backend). Never
  embed an API key in the binary or commit one.
- **Backward-compatible data.** SwiftData migrations are additive/lightweight; never drop
  or corrupt user data. Server migrations via Drizzle are additive.
- **One design system across platforms.** Web uses the same tokens, type scale, spacing,
  radii, and component rules as iOS. The aesthetic is the **light, pure-neutral "life OS"
  look** (white surfaces, black primary buttons, Newsreader serif headings + Hanken
  Grotesk body, hairline-bordered cards) — NOT the current dark `neutral-950`/Geist
  scaffold. SF Symbol-equivalent icons only; no emoji in UI.
- **No new parallel systems.** Extend the Coach orchestrator, `SubApp`/`SubAppRegistry`,
  `CreditsLedger`/`CreditStore`, `CloudSyncService`, and the `web/` app. Consolidate.
- **Removing code is allowed** when it's dev-only/dead/unsafe to ship — gate behind
  `#if DEBUG` rather than deleting useful dev tooling.

---

## 1. Codebase Context (real anchors — verified; do not invent file names)

**iOS stack:** SwiftUI + SwiftData. Entry `PulseLoop/PulseLoopApp.swift` → `RootAppView`
(`Views/RootViews.swift`). Coach chat `Views/CoachView.swift`. Targets: `PulseLoop`,
`PulseLoopWatch`, `PulseLoopWidgets`, `PulseLoopLiveActivity`.

**Backend stack:** `web/` is Next.js 16 + React 19 + Tailwind v4 + Drizzle ORM + Neon
Postgres + Clerk auth (`web/package.json`). Existing API routes ONLY:
- `web/src/app/api/ingest/metrics/route.ts` — device metric upload.
- `web/src/app/api/metrics/route.ts` — dashboard read.
- `web/src/app/api/pair/redeem/route.ts` + `api/devices/pair/route.ts` — 6-char device
  pairing → device token.
- `web/src/db/schema.ts` (Drizzle), `web/src/lib/{auth,device}.ts`.
- **THERE IS NO `/v1/coach/responses` AND NO CREDITS/BILLING ENDPOINT.** The iOS
  `BackendProxyResponsesClient` POSTs to a route that does not exist yet.

**Web app — current state (read-only dashboard; wrong aesthetic):**
- `web/src/app/dashboard/page.tsx` (header + `PairDevice` + `MetricsPanel`),
  `dashboard/metrics-panel.tsx`, `dashboard/pair-device.tsx`, sign-in/sign-up. **None of
  the iOS feature surfaces exist on web.**
- `web/src/app/layout.tsx` sets `bg-neutral-950 text-neutral-100` with `Geist`/`Geist_Mono`;
  dashboard uses `border-neutral-800`, `bg-emerald-400`. This is a generic DARK theme — it
  does NOT match the iOS light "life OS" system and must be re-skinned (Phase G).

**iOS design tokens to port (source of truth):**
- `PulseLoop/App/AppTheme.swift`: `PulseColors` (background/canvas/fillSubtle/fillMuted/
  borderHairline/borderStrong/textPrimary/textSecondary/textMuted/textFaint/accent + metric
  colors: heartRate/alert `#B4453A`, steps/success/battery `#2F7D5B`, spo2/info/distance
  `#4A7FB5`, sleep `#6B5FA0`, sleepScore `#8B7CFF`, calories `#C47230`, readiness `#5B7D2F`,
  warning `#B8860B`); `PulseFont` (Newsreader serif titles, Hanken Grotesk body);
  `PulseRadius` (small 10, medium 14, large 20, xLarge 24, pill 999);
  `PulseLayout.minTapTarget = 44`. Color assets in `PulseLoop/Assets.xcassets/*`.
- `.cursor/rules/design-system.mdc` is the written law (20px page padding, 16–20px card
  padding, 14–16px card radius, 44px buttons, black primary, hairline borders, uppercase
  tracked muted section labels, calm whitespace, SF Symbols only, no emoji).

**The money path — current state (the core gap):**
- `PulseLoop/Services/CreditsLedger.swift` — local, UserDefaults-backed balance +
  `meter(_:usage:)`/`grant(_:)`/`canAfford(_:)`/`syncAuthoritativeBalance(_:)`.
- `PulseLoop/Services/CreditStore.swift` — StoreKit 2 wrapper for ids
  `com.pulseloop.credits.{100,500,1200}`. **No `.storekit` config file exists; no App Store
  Connect products; purchases are NOT server-validated.**
- `PulseLoop/Coach/OpenAI/BackendProxyResponsesClient.swift` — posts the verbatim Responses
  body to `{baseURL}/v1/coach/responses` with a bearer token; handles `402` →
  `insufficientCredits`; adopts `pulseloop_credits.balance`. **Seam built; server missing.**
- `PulseLoop/Coach/Config/CoachSettings.swift` — `CoachProviderMode { offlineStub,
  userOpenAIKey, backendProxy, bedrock }`; `backendProxyURL`.

**Two AI stacks (must consolidate / gate):**
- **Coach** (`PulseLoop/Coach/`) — OpenAI Responses via `Coach/OpenAI/OpenAIResponsesClient.swift`;
  loop in `Coach/Orchestration/CoachOrchestrator.swift`; tools via `Coach/Tools/ToolRegistry.swift`.
- **Legacy `AIService`** (`PulseLoop/Services/AIService.swift`) — OpenRouter, Keychain key
  (plaintext key already removed). Used by meal/label scan, notes AI, inbox, command palette,
  `ProductResearchService`. **Billing-blind.** Flagged for retirement.

**Cloud sync — current state:** `PulseLoop/Services/CloudSyncService.swift` pairs via 6-char
code → device token (Keychain via `CloudSyncKeychainStore`), uploads recent `Measurement`s.
Reads `PULSELOOP_WEB_URL` from Info.plist. **No on-device account, no consent gate before
upload, no data export, no account deletion.**

**Onboarding / demo data:** `OnboardingFlowView` (Welcome → Name → Health → Privacy →
Comfort). Clean installs do NOT auto-seed (`-seedDemo`/`seedDemo` gates `SeedData.seed`).
**The "Reseed demo data" Settings affordance + `-seedDemo` should be `#if DEBUG`-gated.**

**Quality infra:** `.github/workflows/ci.yml` selects `Xcode_16` on `macos-15`, iPhone 16
Pro. **Stale: the voice stack requires Xcode 26.5 / Swift 6.2+ (`docs/VOICE_PROGRESS.md`).**
Tests in `PulseLoopTests/` (unit-level; no UI automation). **No crash reporting/analytics.**

**Known product bug (README):** Sleep page shows last *recorded* night, not last night.

**Design system:** `App/AppTheme.swift`, `DesignSystem/Components.swift`,
`.cursor/rules/design-system.mdc`.

---

## 2. Architecture Target (what "deliverable" means concretely)

### 2.1 Real, abuse-proof money path
- **Server AI proxy.** Implement `web/src/app/api/v1/coach/responses/route.ts` matching
  `BackendProxyResponsesClient`'s contract: authenticate the device/user, check server
  credit balance, forward to OpenAI with the *server's* key, meter actual token usage,
  debit credits, return the response plus `pulseloop_credits.balance`; `402` when out.
- **Server credit ledger.** Drizzle tables for users/credits/transactions; credits live
  server-side as source of truth. iOS `CreditsLedger` becomes a cache synced via
  `syncAuthoritativeBalance(_:)`.
- **Real StoreKit + receipt validation.** Add a `.storekit` config (matching the three
  product ids) for local testing, document the App Store Connect products, and add a server
  endpoint that validates the App Store transaction (App Store Server API / signed
  transaction) before granting credits server-side. Client never self-grants paid credits.
- **One enforced AI path for paying users.** When not BYO-key, all AI (Coach AND legacy
  `AIService` features) routes through the proxy so every call is metered.

### 2.2 App-Store-legal health product
- **Privacy policy + consent.** A consent screen before ANY cloud upload
  (`CloudSyncService`), a linkable privacy policy (host on `web/`), on-device-only default.
  HealthKit/Bluetooth usage strings audited in `Info.plist`.
- **Data rights.** Export-my-data and delete-my-account flows (local + server) from Settings.
- **Account model (decided: real accounts).** Clerk-backed account on iOS to unlock server
  credits, reconciled with the existing pairing-code device link.

### 2.3 Provider strategy (decide & gate)
- Shipping matrix: **proxy (paid) + userOpenAIKey (BYO) shipped; `offlineStub` dev-only;
  Bedrock + OpenRouter behind a build flag** unless part of launch. Gate non-shipping modes
  so the UI never offers an unsupported path.
- **Consolidate or meter `AIService`.** Route its calls through the same proxy (scan/notes/
  inbox billed too) or retire it onto the Coach transport. No billing-blind AI in a paid build.

### 2.4 Ship hygiene (remove / gate)
- `#if DEBUG`-gate `DebugView`, debug repositories, `-seedDemo`/"Reseed demo data", dev-only
  Settings rows. Replace `web/README.md` boilerplate. Fix the Sleep "last recorded vs last
  night" bug. Audit `Info.plist` capabilities + usage strings.

### 2.5 Quality + observability
- **CI on the real toolchain** (Xcode 26.5+/Swift 6.2+); ensure tests run; add `web/`
  `npm run build` + `lint` lane.
- **Crash + error reporting** (MetricKit-first or hosted) + opt-in, content-free analytics.
- **End-to-end correctness sweep:** real empty/loading/error/offline states on every route;
  no force-unwraps on network JSON; full accessibility (Dynamic Type, VoiceOver, 44pt).

### 2.6 Shared principles
- Extend existing seams; additive migrations only (iOS + server); security first (keys
  server-side or Keychain; validate purchases server-side; consent before upload).

### 2.7 Web design-system parity (port the tokens, don't reinvent)
- Single web token source mirroring iOS: a `globals.css` `@theme` (Tailwind v4) + a small
  `tokens.ts` exporting the same color hexes, radius scale, spacing scale, type ramp (e.g.
  `--color-text-primary`, `--color-border-hairline`, `--radius-card: 14px`, `--tap-min: 44px`).
- Load the **same fonts**: Newsreader (serif headings) + Hanken Grotesk (body) via
  `next/font`, replacing Geist. Switch to the **light** life-OS theme; black primary buttons,
  hairline cards, uppercase tracked muted section labels.
- Shared web component kit mirroring iOS by name/behavior: `Card` (≈`PulseCard`),
  `PrimaryButton`/`SecondaryButton`, `Chip`/`StatusChip`, `MetricTile`, `SectionLabel`,
  `ProgressRing`, `Sparkline`, nav. SF Symbol-equivalent monochrome icons; never emoji.
  `.cursor/rules/design-system.mdc` is the cross-platform contract.

### 2.8 Web feature parity with iOS
- Web reaches parity reusing the **same backend** (Phases C/D) and data model: Home/Today,
  Tracker (meals/protocol/wellness), Sleep, Activity, Vitals, Notes, Tasks, Journal, Mood/
  Stress/Meditation, Coach chat (via the server AI proxy), sub-apps/registry, Credits/billing.
  Device-only features (BLE ring, HealthKit, Live Activity, on-device STT/TTS) are out of
  scope for web and degrade gracefully (web reads ring data synced via `CloudSyncService`).
- Parity is **driven by the shared server**, not duplicated logic: iOS + web are two clients
  of one backend. The declarative `SubAppSpec`/runtime ports to a web runtime rendering the
  same specs with web design-system widgets.

### 2.9 Desktop-portability architecture (Tauri Windows/macOS later)
- Structure `web/` so a **Tauri** wrapper ships later with minimal change:
  - **Platform-agnostic core** (`web/src/core/`): data types, API client, state, formatting,
    sub-app runtime — **no `window`/`document`/Next-server-only assumptions** in core logic.
  - **Capability interfaces** (storage, notifications, file export, deep links, open-external)
    with a web impl now and a Tauri impl later. No direct browser-API calls scattered through
    features.
  - **Relative/configurable API base URLs**; no browser-only auth assumptions so the same UI
    runs in a Tauri webview against the same backend. Desktop-safe routing (no full-page-reload
    reliance).
  - Document the Tauri seam + portability checklist in the tracker; do NOT add the desktop
    target yet — just keep the door open.

---

## 3. Roadmap (ordered; each item = one safe, shippable iteration)

**Phase A — Ship hygiene & truth (low-risk, do first)**
- A1. `#if DEBUG`-gate all dev-only surfaces (`DebugView`, debug repos, `-seedDemo`, "Reseed
  demo data", debug Settings rows). Verify a release build exposes none.
- A2. Fix CI: update `.github/workflows/ci.yml` to the toolchain the app builds with
  (Xcode 26.5+/Swift 6.2+); confirm tests run. Add a `web/` build+lint job.
- A3. Fix the Sleep "last recorded vs last night" bug; add a test.
- A4. Replace `web/README.md` boilerplate with a real backend README (env vars, deploy,
  endpoints). Audit `Info.plist` usage strings + capabilities.

**Phase B — Provider strategy & AI consolidation**
- B1. Decide + document the shipping provider matrix; gate non-shipping `CoachProviderMode`s
  so the UI only offers supported paths (`offlineStub` dev-only).
- B2. Route the legacy `AIService` features through the metered path (proxy when not BYO-key)
  OR retire `AIService` onto the Coach transport. No billing-blind AI in a paid build.

**Phase C — Real backend: AI proxy (the core money path)**
- C1. Add Drizzle tables (users, credits balance, credit transactions) + migration.
- C2. Implement `web/.../api/v1/coach/responses/route.ts`: auth → balance check → forward to
  OpenAI with the server key → meter tokens → debit → return body + `pulseloop_credits.balance`;
  `402` when out. Match `BackendProxyResponsesClient`'s contract exactly.
- C3. Wire iOS: confirm `backendProxy` mode end-to-end (balance sync, 402 handling,
  enforcement); add a "buy credits" deep-link from the out-of-credits state.

**Phase D — Real billing (StoreKit + server validation)**
- D1. Add a `.storekit` config matching the three product ids; document the App Store Connect
  setup. Paywall loads real products locally.
- D2. Server endpoint to validate the App Store transaction (signed transaction / App Store
  Server API) and grant credits **server-side**; client stops self-granting paid credits.

**Phase E — Legal & data rights (App Store gate)**
- E1. Consent screen before any `CloudSyncService` upload; privacy policy page on `web/` +
  linked from onboarding/Settings; on-device-only default.
- E2. Data export (local + server) and account/device deletion flows in Settings.
- E3. Clerk-backed account on iOS reconciled with the device pairing link.

**Phase F — Quality & observability (ship-readiness)**
- F1. Crash/error reporting (MetricKit-first or hosted) + opt-in, content-free analytics seam.
- F2. End-to-end correctness sweep: every route's empty/loading/error/offline states; remove
  force-unwraps on network JSON; accessibility audit on all shipped surfaces.
- F3. UI smoke coverage where feasible + a release-build checklist (signing, capabilities,
  App Store metadata) in the tracker.

**Phase G — Web design-system parity**
- G1. Port iOS tokens into `web/`: `globals.css` `@theme` + `tokens.ts` (colors, radii,
  spacing, type ramp); load Newsreader + Hanken Grotesk via `next/font`; flip `layout.tsx` to
  the light life-OS theme. No feature change. `npm run build` + `lint` green.
- G2. Build the shared web component kit mirroring iOS components + `.cursor/rules/
  design-system.mdc`. Re-skin the existing dashboard/pairing/auth screens as the proof.

**Phase H — Web feature parity (one surface per iteration)**
- H1..Hn. Bring each iOS surface to web on the shared backend, design-system-conformant:
  Coach chat (via AI proxy) → Today/Home → Tracker → Sleep/Activity/Vitals (read synced ring
  data) → Notes → Tasks → Journal → Mood/Stress/Meditation → Sub-apps + registry →
  Credits/billing. Each: real API, real empty/loading/error states, accessibility, no
  device-only assumptions.

**Phase I — Desktop-portability hardening (Tauri)**
- I1. Extract the platform-agnostic core (`web/src/core/`): data types, API client, state,
  sub-app runtime — zero `window`/`document`/server-only deps. Build green.
- I2. Capability interfaces (storage, notifications, file export, external links) with web
  implementations; route all browser-API usage through them.
- I3. Document the Tauri wrapper plan + portability checklist; verify the app runs from a
  configurable API base URL with no browser-only auth assumptions. (No desktop target added
  yet.)

---

## 4. THE LOOP PROMPT (paste this each session)

```
You are continuing a long-running project to take the PulseLoop iOS app + its Next.js
(web/) backend from "all feature roadmaps marked done" to a REAL, App-Store-shippable,
abuse-proof product, plus a web app that is a true peer of iOS. Act as a senior frontend
(iOS/SwiftUI + web), backend (Next.js/serverless), and AI engineer. Scope is DECIDED: paid
launch (server proxy + server credits + StoreKit validation + Clerk accounts), web after
backend, Tauri desktop target. Your single source of truth is docs/DELIVERY_LOOP_PROMPT.md
(mission §0, anchors §1, target §2, roadmap §3, guardrails §5) and the live tracker
docs/DELIVERY_PROGRESS.md.

Do EXACTLY ONE iteration, then stop. Follow this loop:

1. ORIENT. Read docs/DELIVERY_LOOP_PROMPT.md and docs/DELIVERY_PROGRESS.md. If
   DELIVERY_PROGRESS.md does not exist, create it from §3 with every item "pending",
   then treat iteration A1 as current.

2. SELECT. Pick the single highest-priority "pending" iteration (top-to-bottom in §3).
   Restate it in one sentence. If too big for one safe step, split it: do the first
   sub-step now and add the remainder as new pending items.

3. PLAN. Write a short todo list for this iteration only. Verify the exact real files/types
   from §1 by reading them — never invent file paths, fields, tool names, endpoints, or
   product ids. Confirm the real BackendProxyResponsesClient contract, CreditsLedger /
   CreditStore API, CloudSyncService shape, CoachSettings / CoachProviderMode cases, web/
   Drizzle schema + existing routes, AIService call sites, and the iOS design tokens before
   using them.

4. IMPLEMENT. Make the change, reusing existing patterns:
   - iOS: SwiftData additive only; design system is law (PulseColors/PulseFont, SF Symbols,
     no emoji, black primary); no secrets in source (Keychain only); no force-unwraps on
     network JSON; gate dev-only surfaces behind #if DEBUG.
   - Backend (web/): extend the existing Next.js 16 + Drizzle + Clerk app; additive
     migrations (drizzle-kit generate); read web/AGENTS.md + node_modules/next/dist/docs
     before writing Next.js code (this Next.js differs from training data); server key stays
     server-side; never trust client-reported credits.
   - AI/money path: server is authoritative for credits; client meters are a cache synced via
     syncAuthoritativeBalance; paid credits granted only after server-side StoreKit
     validation; every AI call in a paid build is metered.
   - Legal/data: consent before any cloud upload; privacy policy linked; data export +
     deletion from Settings; on-device-first default.
   - WEB design: port iOS tokens (App/AppTheme.swift + .cursor/rules/design-system.mdc) into
     web/ — light life-OS theme, Newsreader + Hanken Grotesk, black primary, hairline cards,
     SF Symbol-equivalent icons, no emoji. Reuse the shared component kit; never reinvent.
   - WEB parity: build each surface on the SHARED backend (Phases C/D), not duplicated logic.
     Device-only features degrade gracefully on web.
   - WEB portability: business logic in a platform-agnostic core (no window/document/
     server-only assumptions); browser APIs behind capability interfaces; configurable API
     base URLs — so a Tauri desktop wrapper drops in later.

5. VERIFY. Build and resolve errors before finishing:
   - iOS (Xcode 26.5+/Swift 6.2+):
     xcodebuild -project PulseLoop.xcodeproj -scheme PulseLoop \
       -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
   - web/ (when touched): npm run build && npm run lint
   Run ReadLints on edited files. Add/adjust tests where §3 calls for them. The app (and any
   touched backend) MUST build at the end of the iteration.

6. RECORD. Update docs/DELIVERY_PROGRESS.md: mark this iteration done with a 1–3 line summary
   (what changed + which files + any new models/fields/endpoints/products/flags), list
   follow-ups, and clearly name the NEXT pending iteration.

7. STOP. Post a concise summary: what you did, build status, the next iteration. Do not start
   the next iteration. Do not create a git commit unless explicitly asked.

Rules of engagement:
- Keep both iOS and web/ building; never leave a broken state.
- Prefer small, reversible steps; add fields/endpoints/migrations additively.
- Security first: server-side keys, server-validated purchases, consent before upload. Never
  present a stubbed/dead path as if it works.
- Some steps need credentials only the owner has (App Store Connect products, a deployed
  backend URL + OpenAI server key, a hosted privacy policy, Clerk keys). Implement the code,
  then STOP with a clear "I need X from you" rather than fabricating secrets.
- If a decision has real product trade-offs, state your default, proceed, and note it in the
  tracker rather than blocking.
- If you find the roadmap is wrong, propose the fix in the tracker and adjust, but still
  complete one concrete shippable step this iteration.
```

---

## 5. Guardrails (referenced by the loop — the hard rules)

- **Build green every iteration, on the correct toolchain.** iOS under Xcode 26.5+/Swift 6.2+;
  `web/` must `npm run build` clean when touched. Xcode build + ReadLints + `npm run build`/`lint`
  are the gate.
- **The server is authoritative for money.** Credits live server-side; the client ledger is a
  synced cache. Paid credits granted only after server-side StoreKit validation. No client
  self-grant of purchased credits.
- **No billing-blind AI in a paid build.** Every AI call (Coach AND legacy `AIService`) is
  metered through the enforced path when the user isn't BYO-key.
- **No dead/stubbed paths shipped as live.** A provider with no server, a product id with no
  App Store product, or an endpoint that 404s must be gated off, not offered in the UI.
- **Health-domain legality.** Consent before any cloud upload; on-device-first default; privacy
  policy linked; data export + account/device deletion both work. Audit `Info.plist` strings.
- **Security.** No secrets in source — server key stays server-side, user keys in Keychain.
  Never log secrets or health content.
- **Data integrity.** Additive SwiftData + Drizzle migrations; never drop or corrupt user data.
- **No parallel systems.** Extend `CreditsLedger`/`CreditStore`/`BackendProxyResponsesClient`/
  `CloudSyncService`/the `web/` app. Consolidate the two AI stacks; don't add a third.
- **One design system, all platforms.** Web uses the same tokens, type scale, spacing, radii,
  and component rules as iOS (`.cursor/rules/design-system.mdc` is the cross-platform contract):
  light life-OS aesthetic, black primary buttons, hairline cards, Newsreader + Hanken Grotesk,
  SF Symbol-equivalent icons, no emoji, no gradients on interactive elements. Re-skinning to the
  dark Geist scaffold is a regression.
- **Parity through the shared backend, not duplication.** Web features reuse the same API/data/
  Coach/credits as iOS; device-only capabilities degrade gracefully on web.
- **Desktop-portable by construction (Tauri).** Business logic in a platform-agnostic core;
  browser APIs behind capability interfaces; API base URLs configurable.
- **Ship hygiene.** Dev-only surfaces `#if DEBUG`-gated. Real READMEs, not boilerplate.
- **Design system is law (iOS).** `PulseColors`/`PulseFont`/`PulseRadius`/`PulseLayout` +
  components from `App/AppTheme.swift` + `DesignSystem/Components.swift`. SF Symbols only, black
  primary, hairline cards, calm whitespace.
- **Accessibility & quality.** Dynamic Type, VoiceOver, 44pt targets on every shipped surface;
  real empty/loading/error/offline states; no force-unwraps on network JSON; crash reporting.
- **One iteration at a time.** A single shippable step, then stop — keeping the project reviewable.
