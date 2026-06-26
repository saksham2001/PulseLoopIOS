# Life OS — The Next-Generation Voice-First, Self-Improving Super-App (Open Loop Prompt)

_Goal: evolve PulseLoop from "an app with an AI assistant" into a **Life OS**: an
intuitive, voice-first super-app that organizes the user's whole life, lets anyone
build their own modules and **share** them with other users, always routes to the
best LLMs, and whose modules **self-improve and self-update** through agents._

Run this loop **iteration by iteration**. After each iteration: build, fix, keep the
full test suite green, run on the simulator, append a dated entry to
`docs/LIFE_OS_PROGRESS.md`, then move on. Do not stop until every track below is
`done`.

This loop builds **on the seams that already exist** — do not reinvent architecture.
Extend `SubApp` / `SubAppRegistry` / `SubAppSpec` / `AgentRouter` / `AIModel`, not a
parallel system.

---

## NON-NEGOTIABLE: Follow the app design system

Every view, sheet, row, button, chip, and empty state you add or touch MUST follow
`.cursor/rules/design-system.mdc`. A feature is NOT done if it violates it.

- **No emoji anywhere in rendered UI.** `Image(systemName:)` SF Symbols only. (Spec
  validators already reject emoji icons — keep generated/shared modules on-brand.)
- **Colors via `PulseColors.*`** only; accent for rare emphasis. **Primary buttons =
  `Color.black` fill, white text** (height 44, radius 12); secondary = outlined
  `borderStrong`. **Typography via `PulseFont.*`** (serif titles, Hanken body).
- **Cards**: 16–20px padding, 14–16px continuous radius, 1pt `borderHairline`
  (never shadow-only); prefer `PulseCard` / `pulseCardSurface()`.
- **Sheets**: `.presentationDetents`, `.presentationDragIndicator(.visible)`,
  `PulseColors.background`, left-aligned bold 22pt title. Section headers UPPERCASED,
  tracked, muted. `.buttonStyle(.plain)` inside `Button`/`NavigationLink`.

Reuse the existing vocabulary (`PulseCard`, `StatusChip`, module pickers,
`SubAppRuntimeView` widgets). Match it; don't invent a parallel style.

---

## Ground truth (what already exists — build on it)

- **Module platform**: `SubApp` protocol (`PulseLoop/Platform/SubApp.swift`),
  `SubAppRegistry` install/uninstall + versioning
  (`PulseLoop/Platform/SubAppRegistry.swift`), model registration via
  `ModelContainerFactory` (de-duped), per-SubApp routing via `SubAppRouter`.
- **No-code modules**: `SubAppSpec` schema + strict `SubAppSpecValidator`
  (`PulseLoop/Platform/SubAppSpec.swift`), `SpecSubApp` conformer, `SubAppRuntimeView`
  runtime, `DynamicSubAppRecord` JSON-backed storage, `UserSubAppStore`,
  `SubAppBuilderTools` (AI authoring). Versioning hooks: `migrate(...)`,
  `updateNeedsConfirmation(...)`, `availableUpdate(for:)`, `applyUpdate`.
- **AI**: Sakana-style `AgentRouter` (`generalist`/`strategist`/`researcher`/`vision`),
  `AIModel` tiers with `jsonReliableAnchor` + `jsonUnreliableSlugs`,
  `CoachOrchestrator` agent loop with `CoachTraceEvent`, `OpenRouterResponsesClient`.
- **Voice**: `VoiceServices` + `VoiceSessionController` (hands-free listen→think→
  act→speak) and `VoiceCaptureRouter` (transcript → structured plan).
- **Learning/telemetry seams (thin)**: `DailyLearningService`, `MemoryTools`,
  `DiagnosticsService` (`Telemetry` protocol), `SubAppAnalytics`. **No feedback UI, no
  eval harness, no model leaderboard, no sharing/marketplace yet.**

---

## Definition of done (the whole loop)

A user can **run their life by voice**, **build a module by describing it** and
**share it** with others who can install it safely; the assistant **always picks the
best available LLM** for the job and **transparently shows it**; modules **propose and
apply their own improvements** under user control; and the app **captures feedback and
gets measurably better** over time. All on-design, green, and running on the simulator.

---

## Tracks

### T0 — Foundations: feedback + decision logging (the data the loop needs)
Nothing self-improves without signal. Add the capture layer first.

- **Reply feedback**: add an on-design thumbs-up/down + optional "what was wrong" chip
  row to `CoachResponseView` (and the voice confirmation). Persist a `CoachFeedback`
  record (turn id, route/role, model slug, rating, reason, timestamp). No PII beyond
  what the turn already stored.
- **Decision log**: extend `TurnResult` / persist a lightweight `TurnTelemetry` row for
  every turn — chosen `AgentRole`, model slug, tool names used, rounds, token counts,
  latency, parse-recovery used (y/n), error (if any). Route through the existing
  `Telemetry` seam in `DiagnosticsService` (content-free, opt-in).
- Acceptance: every assistant turn writes one decision row; feedback is one tap;
  both are queryable on-device. Tests: feedback round-trips; a turn emits exactly one
  telemetry row with the expected fields.

### T1 — Voice-first "organize my life" (the headline experience)
Make voice the primary way to run the OS, not a side feature.

- **One-tap voice OS**: from the center AI button, a hands-free session that can do
  multi-domain organizing in one breath ("log a 30-min run, add eggs to today's food,
  remind me to call mom at 6, and start planning a weekend in Tahoe"). Reuse
  `VoiceSessionController`; ensure the orchestrator can fan a single utterance into
  multiple tool calls across multiple installed modules in one turn, then **speak a
  concise multi-part confirmation** and show the structured cards.
- **Proactive daily brief by voice**: a "Good morning" brief that reads the day plan,
  surfaces what `DailyLearningService` learned, and asks one useful question. Opt-in.
- **Barge-in & correction**: the user can interrupt/correct mid-confirmation ("no, 6pm
  tomorrow"); the loop revises without restarting the whole turn.
- Acceptance: a single spoken multi-intent request lands writes in ≥2 modules and is
  confirmed by voice, on-design. Tests: a multi-intent transcript fans out to the right
  tools (over a stubbed client); confirmation text is generated deterministically.

### T2 — "Describe it and it exists": conversational module builder
Lower the bar to building a module from "use the builder tool" to "just say it."

- **Build by voice/chat**: "make me a cold-plunge tracker with duration, temperature,
  and how I felt" → `SubAppBuilderTools` authors a valid `SubAppSpec`, the validator
  passes, and the module is created, installed, and **opened** in one flow with a live
  preview. Confirm before install.
- **Iterate by conversation**: "add a photo field" / "show a weekly streak chart"
  edits the spec, bumps the version, and (per `updateNeedsConfirmation`) re-validates
  and applies. Keep all generated UI inside `SubAppRuntimeView` design-system widgets.
- **Quality gate**: never install a spec that fails `SubAppSpecValidator`; surface
  issues as fixable suggestions, not raw errors.
- Acceptance: a non-technical user creates and refines a working module entirely by
  talking. Tests: builder output validates; an edit bumps version + re-validates;
  invalid specs are rejected with actionable issues.

### T3 — Sharing & the community module gallery (the "super-app" unlock)
Let users share modules and install others' modules **safely**.

- **Export/sign**: a `SubAppSpec` exports to a portable, signed bundle (`.pulseapp`
  JSON: spec + author + version + checksum/signature + declared permissions). No
  executable code — specs are declarative and run on the trusted runtime, so installing
  a shared module can never run arbitrary code (state this guarantee in the UI).
- **Import/install**: import via share sheet / link / paste; show a **permission +
  preview consent screen** (what data it stores, what permissions it requests, author,
  version) before install. Decode-and-validate strictly; reject incompatible schema
  majors with a friendly message.
- **Gallery surface**: an on-design "Community Modules" browse/search surface in the
  module picker. For v1 it can be a **local + bundled curated catalog** with a clean
  provider seam (`ModuleGalleryProvider` over `HTTPTransport`, `isConfigured`-gated)
  so a real backend can drop in later without UI churn. Include featured, categories,
  search, install count (local), and per-module changelog (`SubAppChangelogEntry`).
- **Attribution & updates**: installed shared modules track origin `.installed`, the
  author, and an update channel so `availableUpdate(for:)` can offer upgrades with the
  existing confirmation flow.
- Acceptance: User A exports a module, User B imports it via a file/link, reviews
  permissions, installs, and uses it; updates flow through the existing version path.
  Tests: export→import round-trips identically; signature/checksum verifies and a
  tampered bundle is rejected; permission-consent gating; gallery provider parsing over
  a stubbed transport with graceful offline/unconfigured fallback.

### T4 — Always the best LLM: capability registry + auto-routing + transparency
Make "always have the best LLMs" a living system, not a hardcoded default.

- **Model capability registry**: extend `AIModel` into a small, declarative registry of
  candidate models with metadata (slug, tiers it can serve, tool-calling reliability,
  JSON reliability, vision, context window, rough cost/latency class, "recommended").
  Keep `jsonReliableAnchor`/`jsonUnreliableSlugs` semantics intact.
- **Smarter routing**: `AgentRouter` picks the best **role + model** for the turn from
  the registry (e.g. reasoning-heavy → strongest reasoning model; cheap factual →
  fast tier; vision when images), honoring user overrides and the reliability anchor.
  Add a per-role "best available" auto mode (the default) alongside manual pick.
- **Feedback-weighted selection**: use T0's decision log + feedback to nudge model
  choice (e.g. if a model's parse-recovery rate or thumbs-down rate is high for a role,
  prefer the next-best). Pure, testable ranking function; degrade to defaults with no
  data. This is the **measurable self-improvement of routing.**
- **Transparency**: the trace strip already shows route/model — make it show **why**
  ("Reasoning task, routed to <model>") and let the user one-tap "use a different model
  for this." Keep the single-JSON contract intact for every model.
- **Refresh seam**: a `ModelCatalogProvider` (over `HTTPTransport`, `isConfigured`-
  gated) that can refresh the candidate list from OpenRouter's model list so new
  best-in-class models appear without a code change; bundled fallback when offline.
- Acceptance: routing chooses sensible models per task and visibly explains itself;
  poor-performing models get de-prioritized from real signal; users can override.
  Tests: ranking function (pure) over synthetic logs; routing picks expected model per
  task class; catalog provider parsing over a stubbed transport; anchor/override rules
  preserved.

### T5 — Self-improving modules (agents that propose + apply upgrades, safely)
Modules should get better on their own — under user control, never silently breaking.

- **Module improvement agent**: a scheduled/opportunistic agent (build on
  `DailyLearningService`'s once-a-day pattern) that, per installed module, reviews usage
  (`SubAppAnalytics`), recoverable errors, and feedback, then **proposes** concrete
  improvements: a new field, a more useful screen, a better default, a helpful chart,
  or a fixed validation issue. Output is a candidate `SubAppSpec` diff, not a live edit.
- **Safe apply pipeline**: every proposal is (1) validated by `SubAppSpecValidator`,
  (2) versioned (semantic bump), (3) gated by `updateNeedsConfirmation` for anything
  schema-affecting (data-preserving migrations via `migrate(...)`), and (4) presented
  in an on-design "Suggested improvement" card with a clear diff + one-tap Apply /
  Dismiss. Auto-apply allowed ONLY for non-breaking, opt-in "let modules auto-update"
  per module; everything else requires confirmation. Never lose user data.
- **Self-healing**: when a module logs repeated recoverable errors, the agent prioritizes
  a fix proposal and flags it.
- Acceptance: a module accrues a sensible, validated improvement proposal the user can
  apply; applying preserves existing records; breaking changes always ask first.
  Tests: proposal always validates or is rejected; migration preserves records; a
  breaking change triggers confirmation; auto-update only fires for non-breaking + opt-in.

### T6 — App-level continuous improvement loop (eval harness + dashboard)
Close the loop so the **app itself** improves, not just modules.

- **Lightweight eval harness**: a `PulseLoopEvals` test target/suite of representative
  prompts per role (organize-by-voice, build-a-module, research, reasoning, vision)
  with assertions on shape (valid `coach_response`, no em dash, right tools called,
  saveable cards). Runs over a stubbed/replayed client so it's deterministic in CI.
- **Quality dashboard (dev/settings, on-design)**: surface aggregate signal from T0 —
  per-role thumbs-up rate, parse-recovery rate, top failing tools, per-model win rate —
  so regressions are visible. On-device only.
- **CI wiring**: ensure the eval suite + full test suite run in `.github/workflows/ci.yml`.
- Acceptance: evals run green in CI; the dashboard reflects real on-device signal;
  a regression in route/model quality is observable. Tests: the eval harness itself is
  green and deterministic; dashboard aggregation is a pure, tested function.

---

## Acceptance for the whole loop
- [ ] iOS builds green; **full test suite green each iteration**; runs on the simulator.
- [ ] No emoji in any rendered UI; all new UI uses `PulseColors`/`PulseFont`, black
      primary buttons, hairline cards, design-system sheets.
- [ ] **Voice-first**: a single spoken multi-intent request organizes ≥2 modules and is
      confirmed by voice, with visible cards.
- [ ] **Build by talking**: a non-technical user creates + refines a working module by
      conversation; invalid specs are always rejected with actionable issues.
- [ ] **Share safely**: export→import round-trips; signature/permission consent gates
      install; tampered bundles rejected; a community gallery surface exists with a real
      provider seam + offline fallback.
- [ ] **Best LLM, transparently**: routing picks + explains the model per task, honors
      overrides + the reliability anchor, and de-prioritizes poor performers from real
      feedback; catalog refreshable from a provider seam.
- [ ] **Self-improving modules**: agents propose validated, versioned improvements;
      apply preserves data; breaking changes confirm; auto-update only when non-breaking
      + opted in.
- [ ] **Continuous improvement**: a deterministic eval harness runs in CI and an
      on-device quality dashboard reflects real signal.

---

## Engineering rules for every iteration
- Build on existing seams (`SubApp*`, `AgentRouter`, `AIModel`, `Coach*`,
  `Voice*`, `Telemetry`, `HTTPTransport`); do not fork a parallel architecture.
- Networked work goes behind the existing `HTTPTransport` protocol with
  `isConfigured` gating and graceful offline/unconfigured fallback (mirror the
  wearables `REPLACE_*` pattern); no raw `URLSession` in views/tools.
- Keep the single-JSON `coach_response` contract intact for every model and role.
- Pure logic (ranking, valuation, aggregation, validation) is extracted and
  unit-tested; UI changes verified on the simulator.
- Never lose user data; schema-affecting changes go through `migrate(...)` +
  `updateNeedsConfirmation`.
- Append a dated entry to `docs/LIFE_OS_PROGRESS.md` after each track.
