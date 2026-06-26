# PulseLoop → Intuitive, Module-Aware Experience — Loop Prompt

> **How to use this file.** Paste the section titled **"THE LOOP PROMPT"** (§4) into the Cursor agent as a single
> message at the start of each working session. The agent picks up the roadmap, does **exactly one iteration**,
> updates the tracker (`docs/EXPERIENCE_PROGRESS.md`), and stops. Re-run to advance the next iteration. Everything
> else here (persona, mission, anchors, roadmap, guardrails) is reference material the prompt points at — keep it
> in the repo.

---

## 0. Operating Persona (who "you" are every iteration — never changes)

You operate as a **team of 10 senior frontend + backend engineers** shipping a consumer-grade product. Embody the
whole team's judgment in every iteration:

- **2 × iOS/SwiftUI engineers** — own the app's UI/UX, design-system fidelity, navigation, accessibility.
- **2 × backend engineers** — own the `web/` Next.js backend, OpenRouter proxy, credits ledger, data contracts.
- **1 × AI/agent engineer** — owns the Coach orchestrator, prompts, response schema, tool routing, module awareness.
- **1 × design-systems engineer** — guards `PulseColors`/`PulseFont`/`PulseCard` parity across iOS + web.
- **1 × data/integrations engineer** — owns connectors (HealthKit, ring BLE, GPS, cloud sync, account links).
- **1 × QA engineer** — owns smoke/unit coverage, empty/loading/error states, regression checks.
- **1 × platform engineer** — owns the `SubApp`/`SubAppRegistry`/spec runtime, versioning, migrations.
- **1 × tech lead** — sequences work, enforces guardrails, keeps `main` green, makes the default call on trade-offs.

**How the team works:** small reversible steps; design before code on anything ambiguous; the app **always builds
and runs** at the end of an iteration; every surface obeys the design system; no secrets in source; generated
sub-apps stay declarative (no arbitrary code). When a decision has real product trade-offs, the tech lead states a
default, proceeds, and records it in the tracker for review rather than blocking.

---

## 1. North-Star Vision (the fixed mission)

Make PulseLoop feel **intuitive, adaptive, and trustworthy** by delivering three initiatives to completion:

### Initiative 1 — Connectors that actually work, with correct UI/UX
Every data connector (Apple Health / HealthKit, the smart ring over BLE, GPS workouts, cloud sync / web pairing,
and "Connect accounts") must (a) **function end-to-end**, (b) **show honest, accurate status** (connected /
syncing / last-synced / error / not-available), and (c) **match the design system**. No more aspirational
"coming soon" toggles that pretend to connect. A connector is either real and wired, or clearly labeled as
unavailable with a disabled affordance — never a fake success.

### Initiative 2 — A genuinely intuitive, module-aware chat (not "a coach")
The chat must stop behaving like a narrow health coach that forces every reply into a clinical insight card.
It should:
- **Respond in the right shape for the message.** Casual/social/off-topic → a natural conversational reply.
  A data question → an insight (with chart when useful). A "do X" → an action/confirmation. Never wrap "I'm
  horny" (or any casual line) in a heart-rate analysis card.
- **Adapt to installed modules.** What the chat can do, suggests, and surfaces is driven by which sub-apps the
  user has **installed** (`SubAppRegistry.installedSubApps` + per-module `aiTools`). If a relevant module isn't
  installed, offer to install it instead of failing or pretending.
- **Feel like a command center for the whole life-OS**, with module-aware entry points, suggestions, and empty
  states — reframed from "Coach" to an adaptive assistant.

### Initiative 3 — A real Module (sub-app) browsing experience
Redo the module page so users can:
- **Browse modules with rich detail** — what each does, screenshots/preview, permissions, author, category,
  what data it reads/writes, and the AI tools it adds.
- **See and choose versions** — current installed version, available update, version history/changelog, and
  what a given version changes (leveraging the existing `SemanticVersion` + `availableUpdate`/`installedVersion`
  ledger in `SubAppRegistry`). Updating respects the confirmation path for risky migrations.
- Install / uninstall / update cleanly, with honest state and design-system-correct UI.

**Non-negotiables (every iteration):**
- App **always builds and runs**; `web/` always `next build` + `eslint` clean when touched.
- **Design system is law** (iOS: `.cursor/rules/design-system.mdc`; web: the ported tokens in
  `web/src/app/globals.css` + `web/src/components/ui.tsx`). SF Symbols only, no emoji in UI, primary buttons black.
- **No secrets in source.** Provider = **OpenRouter** (web `OPENROUTER_API_KEY`; iOS Keychain). There is no OpenAI
  dependency in the web backend.
- **Honest UX.** Never show a success/connected/synced state that isn't real.
- **Declarative sub-apps only** — no arbitrary code execution.
- **Additive SwiftData migrations** — never drop user data.

---

## 2. Codebase Context (real anchors — verify by reading; do not invent paths)

**iOS app** — SwiftUI + SwiftData. Entry `PulseLoop/PulseLoopApp.swift` → `RootAppView`
(`PulseLoop/Views/RootViews.swift`). Design system in `PulseLoop/App/AppTheme.swift`
(`PulseColors`, `PulseFont`, `PulseRadius`, `PulseLayout`, `PulseCard`) + `PulseLoop/DesignSystem/Components.swift`.

**Web backend** — `web/` (Next.js 16 / React 19 / Tailwind v4 / Drizzle / Neon / Clerk). Design tokens
`web/src/app/globals.css` + `web/src/lib/tokens.ts`; component kit `web/src/components/ui.tsx`. Coach routes
`web/src/app/api/v1/coach/responses/route.ts` (device, OpenRouter via `web/src/lib/openrouter.ts` +
`web/src/lib/coach-session.ts`) and `web/src/app/api/v1/coach/web/route.ts` (Clerk session). Web Coach UI
`web/src/app/coach/`. Credits `web/src/lib/credits.ts`.

**Initiative 1 — connectors:**
- `PulseLoop/Services/HealthKitIngestion.swift` — Apple Health read/ingest.
- `PulseLoop/RingProtocol/RingBLEClient.swift`, `RingEventBridge.swift`, `PulseLoop/Services/RingSyncCoordinator.swift` — smart ring BLE.
- `PulseLoop/Services/GpsRouteRecorder.swift` — GPS workout recording.
- `PulseLoop/Services/CloudSyncService.swift` — web pairing / cloud sync (+ consent gate).
- `PulseLoop/Views/ConnectAccountsView.swift` + `PulseLoop/Services/AccountConnector.swift` — the "Connect" screen
  (today: `connectedAccounts` is a cosmetic `@AppStorage` set + "coming soon" copy — a prime Initiative-1 target).
- `Info.plist` usage strings (location + Bluetooth) already added.

**Initiative 2 — chat:**
- `PulseLoop/Views/CoachView.swift` — the chat screen (the screenshot surface).
- `PulseLoop/Coach/Orchestration/CoachOrchestrator.swift` — agent loop (rounds, tools, traces, `previousResponseId`).
- `PulseLoop/Coach/Context/CoachPromptBuilder.swift` — system/developer prompts (already pushes "engage naturally").
- `PulseLoop/Coach/Schema/CoachResponseSchema.swift` → `CoachResponse` → `PulseLoop/Coach/Schema/CoachResponseView.swift`
  — the **strict JSON card schema**. This is why casual replies render as clinical cards; making the *shape adaptive*
  (conversational vs. insight vs. action) is the core of Initiative 2.
- `PulseLoop/Coach/Tools/ToolRegistry.swift` + `SubAppRegistry.aiTools(flags:)` — module-scoped tool contribution.
- `PulseLoop/Coach/Config/CoachSettings.swift` (`CoachPersonality`, provider modes).

**Initiative 3 — modules:**
- `PulseLoop/Platform/SubAppRegistry.swift` — install/uninstall, per-module `SemanticVersion`, `availableUpdate(for:)`,
  `installedVersion(of:)`, `applyUpdate`, `updateNeedsConfirmation`.
- `PulseLoop/Platform/SubApp.swift` (protocol) — `displayName`, `iconSystemName`, `summary`, `version`, `author`,
  `origin`, `models`, `aiTools`, `permissions`, etc.
- `PulseLoop/Views/ModulePickerView.swift` — current grid of toggleable module cards.
- `PulseLoop/Views/ModuleUpdatesView.swift` — current updates surface.
- `PulseLoop/Platform/SubAppSpec*` / `SpecSubApp` / `BuiltInSpecs` — declarative spec sub-apps.

**Cross-platform parity:** any chat/module concept should land on **iOS first** (the primary surface), then be
mirrored on `web/` using the shared component kit so the two stay consistent.

---

## 3. Phased Roadmap (ordered backlog — work top-to-bottom)

Track status in `docs/EXPERIENCE_PROGRESS.md` (create on iteration C1 if missing). Each iteration is small,
shippable, and leaves both the iOS app and (if touched) the web app building.

### Track C — Connectors that work with correct UI/UX (Initiative 1)
- **C1.** Audit every connector and write a truth table in the tracker: HealthKit, ring BLE, GPS, cloud sync,
  account links — for each, what's *real* vs. *cosmetic* today, and the target state. Define a shared
  `ConnectorStatus` model (`.connected/.syncing/.lastSynced(Date)/.error(String)/.unavailable`).
- **C2.** Rebuild `ConnectAccountsView` to render **real** status from the actual services (HealthKit authorization,
  ring connection state, cloud-sync pairing) instead of the cosmetic `connectedAccounts` set. Disable/clearly label
  anything genuinely not implemented; remove fake "connected" toggles.
- **C3.** HealthKit connector: verify authorization + ingestion path end-to-end; surface accurate authorized/denied
  + last-import status and a working "import now" action with empty/error states.
- **C4.** Ring BLE connector: surface real scan/connect/battery/last-sync status; handle off/again/error paths in UI.
- **C5.** Cloud sync / web pairing connector: surface real paired account (`linkedAccount`) + last sync + consent;
  honest error/disconnected states. (Builds on the existing E1–E3 work.)
- **C6.** QA pass: a `ConnectorStatusTests`-style suite + smoke coverage for each connector's status mapping and the
  rebuilt UI's states.

### Track M — Adaptive, module-aware chat (Initiative 2)
- **M1.** Make the response **shape** adaptive. Add an explicit conversational mode to the schema/rendering so a
  casual/social/off-topic message renders as a plain chat bubble (not an insight card). Define the decision rule
  (in `CoachPromptBuilder` + `CoachResponseSchema`/`CoachResponseView`) and prove it: "I'm horny" / "good morning" /
  "tell me a joke" must NOT produce a health card.
- **M2.** Make the chat **module-aware in the UI**: greeting, suggestions, and follow-up chips derived from
  `SubAppRegistry.installedSubApps` (e.g. no Sleep module ⇒ no sleep suggestions). Empty/first-run state reflects
  installed modules.
- **M3.** Module-aware **capability routing**: when the user asks for something a non-installed module would handle,
  the chat offers to install it (via the existing platform-control tools) instead of failing or faking it.
- **M4.** Reframe "Coach" → adaptive assistant across the surface (naming, header, entry points, personalities still
  available) without breaking existing threads.
- **M5.** Mirror the adaptive behavior on the **web** Coach (`/coach`): conversational vs. structured replies and
  module-aware suggestions where web data allows; keep provider = OpenRouter.
- **M6.** QA pass: tests for the shape-decision (conversational vs. insight vs. action) and module-aware
  suggestion/tool gating; verify no regression to the strict-schema tool/chart flows.

### Track P — Module browsing & versions (Initiative 3)
- **P1.** Design + build a **Module Detail** view: full description, icon, category, author, permissions, what it
  reads/writes, the AI tools it adds, and install/uninstall/update actions — all design-system-correct.
- **P2.** Surface **versions**: installed version, available update, and a **changelog/version history** per module
  (extend `SubApp`/`SemanticVersion` with a lightweight changelog source). Show "what changed".
- **P3.** Rebuild the **module browse page** (evolve `ModulePickerView`) into a real catalog: categories, search,
  "installed" vs. "available", "updates available" section (fold in `ModuleUpdatesView`), each card → Module Detail.
- **P4.** Version selection / update flow from detail: update with the existing confirmation path for risky
  migrations; honest post-update state.
- **P5.** Mirror a lightweight module catalog + detail on **web** using the shared component kit (read-only or
  install-aware as the backend allows).
- **P6.** QA pass: tests for version display (`availableUpdate`/`installedVersion`/changelog), install/uninstall/
  update flows, and detail-view state.

### Track W — Web feature parity (the web app gains all mobile features)
> **Goal:** the web app reaches functional parity with the iOS app. Today the web only reads a thin slice of
> *synced metrics* (`metric_samples`) and exposes Dashboard/Today/Coach/Pairing. The iOS app stores ~30+ feature
> domains (Sleep, Activity, Vitals, Tasks, Notes, Journal, Mood, Stress, Meditation, Nutrition, Protocol, Day Plan,
> Friends, Inbox, Sub-Apps, Credits, …) in **local SwiftData that never reaches the backend**. Parity therefore
> requires a **sync/data foundation first**, then a feature-by-feature rebuild on web using the shared component kit.
> Land sync on iOS + backend before building each web surface, so the web shows the user's *real* data, not stubs.

- **W1.** Parity audit + plan: in the tracker, enumerate every iOS feature domain and for each record its SwiftData
  model(s), whether it syncs today (almost all: no), and the target (read-only on web vs. full read/write). Decide
  the sync architecture default (server-authoritative tables + device push, mirroring the existing `metric_samples`
  ingest pattern) and record it in the decision log.
- **W2.** Generic sync foundation — backend: add a versioned, idempotent record-sync contract beyond metrics
  (e.g. `POST /api/v1/sync/push` + `GET /api/v1/sync/pull`) with a generic per-domain table strategy (or typed
  tables), `clientId` upserts, `updatedAt` watermarks, and device-token auth. Drizzle schema + migration.
- **W3.** Generic sync foundation — iOS: a `DataSyncService` that pushes SwiftData changes for opted-in domains and
  pulls remote changes, behind the existing cloud-sync consent gate. Conflict rule = last-writer-wins on
  `updatedAt` (record the default). Start with **one domain** (Tasks) to prove the pipe end-to-end.
- **W4..Wn.** Per-feature web parity, one domain per iteration (priority order; adjust in tracker): **Tasks → Notes
  → Journal → Day Plan → Mood → Stress → Meditation → Nutrition → Protocol → Sleep detail → Activity/Workouts →
  Vitals → Friends/Inbox → Sub-App browse/detail (ties into Track P) → Credits/billing view.** For each: ensure the
  domain syncs (W2/W3), then build the web surface (list/detail/create/edit as parity requires) with the shared
  `web/src/components/ui.tsx` kit + design tokens, plus honest empty/loading/error states and a web nav entry.
- **Wq.** Web parity QA pass: sync round-trip tests (push from iOS fixture → pull on web), and web UI state coverage
  for each shipped domain.

### Track Q — Final hardening
- **Q1.** Cross-initiative polish: accessibility (Dynamic Type, VoiceOver, 44pt targets), consistent empty/loading/
  error states, and a release-readiness pass updating `docs/RELEASE_CHECKLIST.md`.

---

## 4. THE LOOP PROMPT (paste this each session)

```
You are a team of 10 senior frontend + backend engineers (see persona §0) continuing a long-running effort to make
the PulseLoop app intuitive, adaptive, and trustworthy. Your single source of truth is
docs/EXPERIENCE_LOOP_PROMPT.md (persona §0, mission §1, code anchors §2, roadmap §3, guardrails §5) and the live
tracker docs/EXPERIENCE_PROGRESS.md.

Do EXACTLY ONE iteration, then stop. Follow this loop:

1. ORIENT. Read docs/EXPERIENCE_LOOP_PROMPT.md and docs/EXPERIENCE_PROGRESS.md. If the tracker doesn't exist, create
   it from the §3 roadmap with every item "pending", then treat C1 as current.

2. SELECT. Pick the single highest-priority "pending" iteration (top-to-bottom across tracks C → M → P → W → Q,
   unless
   the tracker notes a dependency reordering). Restate it in one sentence. If it's too big for one safe shippable
   step, split it: do the first sub-step now and add the remainder as new pending items.

3. PLAN. Write a short todo list for THIS iteration only. Name the exact real files from §2 you'll touch — verify by
   reading first; never invent paths.

4. IMPLEMENT. Make the change as the whole team would: correct UI/UX AND a sound backend/data path. Obey every
   guardrail in §5. Reuse existing patterns — iOS design system (PulseColors/PulseFont/PulseCard,
   .cursor/rules/design-system.mdc), web token kit (web/src/components/ui.tsx, globals.css), the Coach orchestrator
   (strict JSON schema, tool registry, OpenRouter), and the SubAppRegistry versioning/install APIs. SF Symbols only,
   no emoji in UI, primary buttons black, no secrets in source, OpenRouter (never OpenAI) in the web backend, honest
   connector/module state (never fake "connected"/"synced"/"installed").

5. VERIFY. Build before finishing and resolve errors:
   - iOS:  xcodebuild -scheme PulseLoop -destination 'generic/platform=iOS Simulator' build
     (or run on the booted simulator when a UI change benefits from it).
   - web (if touched): npm run build && npm run lint  (in web/).
   Use ReadLints on edited files. Add/adjust tests where §3 calls for a QA pass. Everything MUST build at the end.

6. RECORD. Update docs/EXPERIENCE_PROGRESS.md: mark the iteration done with a 1–3 line summary + touched files, list
   any follow-ups you spun off, and clearly name the NEXT pending iteration.

7. STOP. Post a concise summary: what you did, build status, and the next iteration. Do not start the next one. Do
   not create a git commit unless explicitly asked.

Rules of engagement:
- Keep main always building; never leave a broken state. Prefer small reversible steps over big rewrites; use
  adapters so old and new paths coexist during a migration.
- Backward-compatible, additive SwiftData migrations only — never drop user data.
- Land changes on iOS first (primary surface), then mirror on web for parity when the track calls for it.
- If a decision has real product trade-offs (response-shape rules, what a connector should show when unavailable,
  what a module-detail page surfaces), state your default, proceed, and note it in the tracker rather than blocking.
- If the roadmap is wrong, propose the fix in the tracker and adjust — but still complete one concrete shippable
  step this iteration.
```

---

## 5. Guardrails (the hard rules the loop enforces)

- **Build green every iteration.** iOS must compile/run; web must `next build` + `eslint` clean when touched.
- **Design system is law.** iOS: `PulseColors`/`PulseFont`/`PulseRadius`/`PulseLayout` + components, per
  `.cursor/rules/design-system.mdc`. Web: tokens in `globals.css` + `web/src/components/ui.tsx`. SF Symbols only,
  no emoji in rendered UI, primary buttons black, hairline-bordered cards, calm whitespace.
- **Honest UX.** A connector/module/sync state shown to the user must reflect reality. Unavailable features are
  clearly disabled/labeled, never faked as working.
- **Provider = OpenRouter.** Web backend uses `OPENROUTER_API_KEY` and the chat-completions translation seam; no
  OpenAI calls/keys. iOS keys live in Keychain. No secrets in source.
- **Adaptive, not rigid, chat.** The response *shape* is chosen by intent (conversational / insight / action);
  never force a casual message into a health card. Capabilities and suggestions are scoped to installed modules.
- **Declarative sub-apps only.** User/AI-generated sub-apps are validated specs interpreted by the runtime — never
  compiled/eval'd code. Versioning + migrations stay additive and confirmed when risky.
- **Data integrity.** Additive, lightweight SwiftData migrations; defaulted new fields; cascade rules as
  established. Never drop user data.
- **Accessibility & quality.** Dynamic Type, VoiceOver labels, 44pt tap targets; tests on each QA pass (connector
  status mapping, chat shape decision, module versioning/install flows).
- **One iteration at a time.** A single shippable step, then stop — keeping the project reviewable.
```
