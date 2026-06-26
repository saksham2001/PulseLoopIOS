# PulseLoop → Modular Sub-App Platform — Loop Prompt

> **How to use this file.** Paste the section titled **"THE LOOP PROMPT"** into Claude (Cursor agent) as a single message at the start of each working session. Claude will pick up the roadmap, do exactly one iteration, update the tracker, and stop. Re-run it to advance the next iteration. The rest of this document (Context, Roadmap, Guardrails) is reference material the prompt points Claude at — keep it in the repo.

---

## 0. North-Star Vision (the fixed mission — never changes between iterations)

Turn **PulseLoop** (a SwiftUI + SwiftData iOS "life OS" / health app) into a **fully modular sub-app platform**:

1. **Everything becomes a Sub-App.** Health, Sleep, Activity, Fitness, Protocol, Nutrition, Tasks, Notes, Journal, Mood, Stress, Meditation, Symptoms/Labs, Quit Program, Friends, Inbox, Day Plan — each is repackaged as a self-contained **Sub-App module** conforming to a single `SubApp` protocol. These ship as the **built-in starter sub-apps**.
2. **Users build their own sub-apps with AI.** A "Sub-App Builder" lets a user describe an app in natural language; the AI generates a sub-app spec (data models, screens, dashboard card, AI tools, settings) that **renders through a safe, declarative runtime** and **automatically inherits the PulseLoop design system** (`PulseColors`, `PulseFont`, `PulseCard`, components in `Components.swift`). No arbitrary code execution — generated apps are **spec-driven**, not raw Swift.
3. **AI usage costs credits.** Building and running AI-powered sub-app features consumes **AI credits** the user purchases. There is a metering + balance + paywall + purchase system. (Today there is **no billing** — the `backendProxy` `CoachProviderMode` stub in `Coach/Config/CoachSettings.swift` is the intended seam.)
4. **Sub-apps are powerful & enterprise-quality.** Robust validation, versioning, migrations, error recovery, permissions/sandboxing, analytics, accessibility, and tests — not toys.
5. **Sub-apps are shareable.** A user can publish a sub-app spec to a registry; others can browse, install, rate, and run it. Sharing transfers the **spec** (declarative), never executable code.
6. **The existing sub-apps get more intuitive & comprehensive** as they are migrated — better empty states, onboarding, comprehensiveness of data, and UX polish, all on the unified runtime.

**Non-negotiables across every iteration:**
- The app must **always build and run** at the end of each iteration. Never leave `main` in a broken state.
- **Design system is law.** Every screen uses `PulseColors` / `PulseFont` / `PulseRadius` / `PulseLayout` and components from `App/AppTheme.swift` + `DesignSystem/Components.swift`. Follow `.cursor/rules/design-system.mdc`. **SF Symbols only, no emoji in rendered UI. Primary buttons are black, not accent.**
- **No secrets in source.** The legacy plaintext OpenRouter key in `Services/AIService.swift` must be removed/secured before any shareable/public feature ships. AI keys live in Keychain (see `Coach/Config/OpenAIKeychainStore.swift`).
- **Generated sub-apps never execute arbitrary code.** They are interpreted from a validated declarative spec.
- **Backward compatible data.** SwiftData migrations are additive/lightweight; never drop user data.

---

## 1. Codebase Context (real anchors — do not invent file names)

**Stack:** SwiftUI + SwiftData (no CoreData, no CloudKit yet). Targets: `PulseLoop` (iOS), `PulseLoopWatch`, `PulseLoopWidgets`. Entry: `PulseLoop/PulseLoopApp.swift` → `RootAppView` (`PulseLoop/Views/RootViews.swift`).

**The three centralization points that block modularity (the core refactor targets):**
1. **Routing** — single `enum AppRoute` + `destinationView(for:)` switch in `App/AppTheme.swift` and `Views/RootViews.swift`.
2. **Persistence** — single `Schema([...])` (~55 `@Model`s) in `Persistence/ModelContainerFactory.swift`. Adding any model requires editing this file.
3. **AI tools** — central `ToolRegistry` in `Coach/Tools/ToolRegistry.swift`.

**Existing (shallow) module system to evolve, not discard:**
- `enum AppModule` + `class ModuleManager` (singleton, `UserDefaults`-backed enable/disable) in `App/AppTheme.swift`.
- `Views/ModulePickerView.swift` (grid of toggleable module cards; used in onboarding + settings).
- Today modules are only feature flags that show/hide sidebar/tracker entries — they are NOT self-contained units.

**Design system:**
- `App/AppTheme.swift` — `PulseColors`, `PulseFont` (Hanken Grotesk body, Newsreader serif titles), `PulseRadius`, `PulseLayout`, components: `PulseCard`, `MetricTile`, `MiniSparkline`, `PrimaryButton`, `SecondaryButton`, `PillToggle`, `StatusChip`, `EyebrowLabel`.
- `DesignSystem/Components.swift` — `ToneChip`, `HeroInsightCardView`, `CoachMessageCard`, `MetricCardButton`, `ProgressRingView`, `DetailCard`, `QuickActionButton`, `ActivitySectionCard`, etc.
- `DesignSystem/ChartViews.swift`, `SleepHypnogram.swift`, `WorkoutMapView.swift` — charts.
- `.cursor/rules/design-system.mdc` — the written design law.

**AI stacks (two — consolidate onto the Coach):**
- **Coach orchestrator** (`PulseLoop/Coach/`) — the "real" agent. OpenAI Responses API via `Coach/OpenAI/OpenAIResponsesClient.swift`. Agent loop in `Coach/Orchestration/CoachOrchestrator.swift` (rounds, tool budget, retries, traces, `previousResponseId`). **Strict JSON schema** output in `Coach/Schema/CoachResponseSchema.swift` → `CoachResponse` → `CoachResponseView`. Tools in `Coach/Tools/` registered via `ToolRegistry.swift`, gated by `Coach/Config/CoachFeatureFlags.swift`. Settings in `Coach/Config/CoachSettings.swift` (`CoachProviderMode`: `offlineStub` / `userOpenAIKey` / `backendProxy` [stub]). Key in Keychain (`OpenAIKeychainStore.swift`).
- **Legacy `AIService`** (`Services/AIService.swift`) — OpenRouter, **hard-coded plaintext key**, no schema/tools, used by `CommandPaletteView`, scan views, notes, inbox. **To be secured/retired.**

**Data-access patterns:** `@Model` types use `@Attribute(.unique) var id: UUID`, `createdAt`/`updatedAt`, enums stored as raw strings + computed typed accessor, additive optional fields with defaults, `@Relationship(deleteRule: .cascade)`. Repositories in `Services/Repositories.swift`; domain services in `Services/PulseServices.swift`.

**Billing/sync today:** none. No CloudKit, no multi-user sync, no credits. `WatchSyncService` is one-way iPhone→Watch. `backendProxy` is the intended seam for server-mediated AI + billing.

---

## 2. Architecture Target (what we are building toward)

### 2.1 The `SubApp` protocol (declarative module unit)
A protocol (e.g. `Platform/SubApp/SubApp.swift`) that bundles everything a feature needs so it stops coupling to the three centralization points:
- `identifier`, `displayName`, `iconSystemName` (SF Symbol), `summary`, `version`, `author`, `origin` (`.builtIn` / `.userCreated` / `.installed`).
- `models: [any PersistentModel.Type]` (contributed to the schema).
- `routes` / a typed destination factory (contributed to navigation).
- `dashboardCard()` (Home), optional `sidebarEntries`, optional `settingsSection`.
- `aiTools: [AnyCoachTool]` (contributed to the Coach `ToolRegistry`).
- `permissions: Set<SubAppPermission>` (health read, write, notifications, network, etc.).

A `SubAppRegistry` (replaces/wraps `ModuleManager`) discovers built-in sub-apps, loads installed/user specs, and feeds models→`ModelContainerFactory`, routes→router, tools→`ToolRegistry`, cards→Home.

### 2.2 Declarative Sub-App Spec (for AI-generated + shareable apps)
A `Codable` `SubAppSpec` (JSON) describing: entities (fields, types, relations), screens (list/detail/form/dashboard built from a fixed catalog of design-system widgets), actions, and AI tool bindings. A **`SubAppRuntime`** interprets a spec into SwiftUI using ONLY design-system components — so generated apps look native and cannot run arbitrary code. Strict validation + versioned schema + migration. This is the enterprise-quality, safe core.

### 2.3 AI Sub-App Builder
A guided flow + Coach tool(s) that turn a natural-language description into a validated `SubAppSpec`, with iterative refinement, preview, and "publish/share." Builder AI calls consume **credits**.

### 2.4 Credits & Billing
- `CreditsLedger` (balance, transactions, metering per AI call: builder + runtime tool calls).
- Paywall + StoreKit 2 purchase of credit packs.
- Server-mediated AI (`backendProxy` mode) so credits can be enforced authoritatively; until the server exists, meter locally against BYO-key as a transitional measure but design the seam for server enforcement.

### 2.5 Sharing / Registry
- Export/import a `SubAppSpec` (signed, validated). Browse/install/rate published sub-apps. Sharing moves **specs only**.

---

## 3. Phased Roadmap (the ordered backlog the loop walks through)

Work strictly top-to-bottom. Each **Iteration** is small, shippable, and leaves the app building. Track status in `docs/MODULAR_PROGRESS.md` (create it on iteration 1).

**Phase A — Foundations & Safety**
- A1. Create `docs/MODULAR_PROGRESS.md` tracker; remove/secure the hard-coded key in `Services/AIService.swift` (move to Keychain/config, fail gracefully).
- A2. Define the `SubApp` protocol + `SubAppRegistry` scaffolding (no behavior change yet; `ModuleManager` delegates to it).
- A3. Make routing pluggable: introduce a router that accepts route contributions from sub-apps; keep `AppRoute` working via an adapter.
- A4. Make the schema pluggable: `ModelContainerFactory` assembles its `Schema` from `SubAppRegistry.allModels` + core models.
- A5. Make `ToolRegistry` accept tool contributions from sub-apps.

**Phase B — Migrate built-in sub-apps (one per iteration) + make each more intuitive/comprehensive**
- B1..Bn. Convert each existing feature into a `SubApp` conformer (start with **Sleep**, then Activity, Health/Vitals, Fitness, Protocol, Nutrition, Tasks, Notes, Journal, Mood, Stress, Meditation, Symptoms/Labs, Quit Program, Friends, Inbox, Day Plan). For each: move its models/routes/tools/card behind the protocol, AND deliver one concrete UX upgrade (better empty state, onboarding, richer data, clearer dashboard card).

**Phase C — Declarative runtime**
- C1. `SubAppSpec` Codable schema + strict validator + versioning.
- C2. `SubAppRuntime` that renders list/detail/form/dashboard screens from a spec using design-system widgets only.
- C3. Spec-driven persistence (dynamic entities) + additive migration strategy.
- C4. Re-express ONE simple built-in (e.g. Mood or a habit tracker) as a spec to prove the runtime end-to-end.

**Phase D — AI Sub-App Builder**
- D1. Coach tool(s) `generate_subapp_spec` / `refine_subapp_spec` with strict JSON schema output (reuse Coach orchestrator patterns).
- D2. Builder UI: describe → preview (live runtime) → refine → save as `.userCreated` SubApp.
- D3. Guardrails: validation, permission prompts, design-system conformance checks, safety review.

**Phase E — Credits & Billing**
- E1. `CreditsLedger` + metering hooks on every AI call (builder + runtime tools).
- E2. Paywall + StoreKit 2 credit-pack purchases + balance UI.
- E3. Enforcement seam via `backendProxy` provider mode (server-authoritative; local transitional fallback).

**Phase F — Sharing / Registry**
- F1. Export/import signed `SubAppSpec`.
- F2. Registry browse/install/rate; install flow with permission review.
- F3. Moderation/safety + versioned updates for installed sub-apps.

**Phase G — Enterprise hardening**
- G1. Per-sub-app analytics, error recovery, accessibility audit, tests for runtime + spec validation + credits ledger.

---

## 4. THE LOOP PROMPT (paste this each session)

```
You are continuing a long-running project: turning the PulseLoop iOS app into a
modular Sub-App platform. Your single source of truth is docs/LOOP_PROMPT.md
(mission §0, code anchors §1, architecture target §2, roadmap §3, guardrails §5)
and the live tracker docs/MODULAR_PROGRESS.md.

Do EXACTLY ONE iteration, then stop. Follow this loop:

1. ORIENT. Read docs/LOOP_PROMPT.md and docs/MODULAR_PROGRESS.md. If
   MODULAR_PROGRESS.md does not exist, create it from the §3 roadmap with every
   item set to "pending", then treat iteration A1 as current.

2. SELECT. Pick the single highest-priority "pending" iteration (top-to-bottom in
   §3). Restate it in one sentence. If it is too big for one safe, shippable step,
   split it: do the first sub-step now and add the remainder as new pending items.

3. PLAN. Write a short todo list for this iteration only. Identify the exact real
   files from §1 you will touch (never invent file paths — verify by reading).

4. IMPLEMENT. Make the change. Obey every guardrail in §5. Reuse existing
   patterns: design system (PulseColors/PulseFont/PulseCard, .cursor/rules/
   design-system.mdc), SwiftData model conventions, and the Coach orchestrator
   patterns (strict JSON schema, tool registry, Keychain keys). SF Symbols only,
   no emoji in UI, primary buttons black, no secrets in source, no arbitrary code
   execution in generated sub-apps.

5. VERIFY. Build the app and resolve errors before finishing:
   xcodebuild -scheme PulseLoop -destination 'generic/platform=iOS Simulator' build
   (use ReadLints on edited files; add/adjust tests where §3 calls for them). The
   app MUST build at the end of the iteration.

6. RECORD. Update docs/MODULAR_PROGRESS.md: mark this iteration done with a 1–3
   line summary of what changed and which files, list any follow-ups you spun off,
   and clearly name the NEXT pending iteration.

7. STOP. Post a concise summary: what you did, build status, and the next
   iteration. Do not start the next iteration. Do not create a git commit unless I
   explicitly ask.

Rules of engagement:
- Keep main always building; never leave broken state.
- Prefer small, reversible steps over big rewrites; use adapters so old and new
  paths coexist during migration.
- Backward-compatible, additive SwiftData migrations only — never drop user data.
- If a decision has real product trade-offs (pricing, data model shape, what a
  "spec" can express), state your default choice, proceed, and note it in the
  tracker for my review rather than blocking.
- If you discover the roadmap is wrong, propose the fix in the tracker and adjust,
  but still complete one concrete shippable step this iteration.
```

---

## 5. Guardrails (referenced by the loop — the hard rules)

- **Build green every iteration.** End state must compile and run. Use the Xcode build/lint as the gate.
- **Design system is law.** `PulseColors`, `PulseFont`, `PulseRadius`, `PulseLayout`, components from `App/AppTheme.swift` + `DesignSystem/Components.swift`. Obey `.cursor/rules/design-system.mdc`. SF Symbols only (no emoji in rendered UI). Primary buttons black, accent used sparingly. Cards have hairline borders, calm/minimal whitespace.
- **Security.** No API keys/secrets in source. Keychain for keys. Remove the legacy plaintext OpenRouter key early (A1).
- **Safety of generated apps.** User/AI-generated sub-apps are **declarative specs interpreted by a runtime** — never compiled/eval'd Swift. Validate strictly, gate permissions, review for safety.
- **Data integrity.** Additive, lightweight SwiftData migrations; defaulted new fields; cascade relationships as established. Never drop user data.
- **Incrementality.** Use adapters so the centralized `AppRoute` / `Schema` / `ToolRegistry` keep working while sub-apps are migrated one at a time.
- **AI consolidation.** Prefer the Coach orchestrator (structured output, tools, gating, Keychain) over the legacy `AIService` for new AI work.
- **Credits everywhere AI runs.** Once Phase E lands, every builder call and every runtime AI tool call meters credits; design the server-enforcement seam (`backendProxy`) even if local-first initially.
- **Accessibility & quality.** Maintain Dynamic Type, VoiceOver labels, 44pt tap targets; add tests for the spec validator, runtime, and credits ledger.
- **One iteration at a time.** The loop does a single shippable step and stops, keeping the project reviewable.
```
