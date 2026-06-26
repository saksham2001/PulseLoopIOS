# Life OS — Progress Log

Dated entries, newest first. One entry per completed track from
`docs/LIFE_OS_LOOP_PROMPT.md`.

---

## 2026-06-25 — Bugfix sweep: green suite + real runtime defects (done)

Drove the working tree back to a deterministically green test suite and fixed a
batch of real runtime bugs surfaced by the suite and a static review of the
uncommitted diff. See `docs/BUGFIX_OPEN_LOOP_PROMPT.md` for the loop used.

**Test fixes (4 failures → 0)**
- Sleep day-range tests were wall-clock fragile: the helpers built `night(0)` from
  `startOfDay(today)`, which diverges from `SleepService.dayReferenceNight()` between
  midnight and 4 AM. Anchored the fixtures on the reference night.
- `testDisabledCoachUsesScriptedFallback` assumed `.default` settings = disabled, but
  the master switch defaults on and the paired-proxy path can enable the coach; added
  an explicit `disabledSettings`.
- Voice synthesis heap corruption (below).

**Real runtime bugs fixed**
- `SleepLog.init` recorded NEGATIVE durations for the normal overnight case (default
  bedtime 22:30 / wake 07:00 same day); roll wake forward a day. Sheet default bedtime
  moved to the prior evening.
- `NoteEditorView.loadNote()` inserted a fresh blank Note on every `.onAppear`
  (orphaned empty notes); guarded to load once.
- TTS `stop()` (Sherpa/OpenAI/Kokoro) fired `onFinish` unconditionally — the pre-speak
  `stop()` reopened the mic and clipped the start of each reply; only fire when speaking.
- `SherpaOnnxAPI.toCPointer` returned an autoreleased `NSString.utf8String` pointer
  stored in C config structs and read later by onnxruntime: a use-after-free that
  corrupted the native heap. Now `strdup`s. Synthesis serialized (`pendingGenerate`)
  and models cached (build-once) to cut native session churn.
- `AccountHTTPClient.authorize()` discarded the OAuth bundle from `connect()`, so the
  token was never saved and every sync threw `.notConfigured`; persist it.
- `log_mood` declared `mood`/`energy` as `number` but decoded `Int` (a `4.0` payload
  threw); now `integer`.
- Bedrock `translateInput` demoted system/developer turns to user messages (400 on the
  first turn); fold them into the Anthropic `system` field.
- `HomeView` lost the whole custom module order if any one enum raw value changed
  (decode loosely as strings); `WeekPlanner` "place selected" never auto-dismissed
  (checked the count after clearing); `MealScan` wrote a stale async result after
  retake (guard on image identity; reset `isAnalyzing`); duplicate `Identifiable` IDs
  dropped travel cards / itinerary days / media (key `ForEach` by position).
- Wearable/travel sync: Oura HR used `+00:00` (URLComponents leaves `+` unencoded →
  read as space) → `Z`; Fitbit zone-less timestamps parsed as UTC (shifted the sleep
  window) → parse in local time; Amadeus token body sent raw secrets → percent-encode.
- `OpenFDA` negative cache returned empty `Data()` on a hit (vs nil on the miss);
  `WhisperEngine` read the render-thread `AVAudioPCMBuffer` later on the main actor
  (use-after-free) → deep-copy in the tap; `TrackerView` `devices.first` on an
  unsorted query → sort by `updatedAt`.

**Verification**
- Full suite green twice: 543 passed, 6 skipped, 0 failures, no heap corruption.
- The 5 real-audio TTS synthesis tests are gated behind `RUN_TTS_SYNTHESIS` (set in the
  scheme's Test env): vendored sherpa-onnx/onnxruntime/espeak use non-reentrant native
  global state that intermittently corrupts the heap under cumulative in-process
  synthesis on the simulator. Each passes in isolation; the app loads only one/two
  models so it is unaffected. App-side hardening (strdup, serialization, model cache)
  reduced it from deterministic to rare but can't fully fix the vendored stack.

---

## 2026-06-24 — T6 Self-improving quality loop: eval harness + quality dashboard (done)

Closed the loop with a deterministic, network-free way to know the assistant is
healthy, plus an on-design readout of real usage.

**Eval harness** (`Coach/Eval/CoachEvalHarness.swift`)
- Pure, provider-free harness over the two contracts the experience rests on:
  ROUTING (a turn classifies to the right specialist via `AgentRouter.route`) and
  SHAPE (a raw model payload, parsed + `adaptiveShaped`, satisfies the rendered
  invariants: no em/en dashes, chart only on `insight_with_chart`, non-empty
  summary, structure).
- Declarative cases: `RoutingEvalCase`, `ShapeEvalCase`, reusable `ShapeAssertion`s
  (`noEmDash`, `chartMatchesType`, `hasSummary`, `type`, `minBullets`). `runAll()`
  returns `[EvalResult]`. Same input → same result, so it never flakes.

**Quality dashboard** (`Coach/Eval/CoachQualityReport.swift`, `Views/CoachQualityView.swift`)
- `CoachQualityReportBuilder.build(in:)` — pure aggregation over the T0 signal
  (`TurnTelemetry` + `CoachFeedback`): per-model rows (turns, up/down, recovery,
  error), headline rates, a top-down-reason histogram, and the eval pass rate.
  Reads on-device only; never throws (zeroed report when empty).
- `CoachQualityView` — on-design read-only screen (PulseCard/PulseColors/PulseFont,
  SF Symbols, no emoji/accent fills): contract-check pass rate with failing cases
  listed, last-N-turns satisfaction/recovery/error, by-model breakdown, top
  complaints. Reachable from Settings → "AI Quality" (`AppRoute.coachQuality`).

**Tests** (`CoachEvalHarnessTests` 6, `CoachQualityReportTests` 4)
- Eval: all default cases pass; routing classifies correctly; em dash always
  stripped; stray chart dropped but kept on the chart type; prose fallback becomes
  the summary; a failing assertion is reported (not swallowed).
- Report: empty report has no signal but still runs evals; rolls up turns/votes by
  model with correct rates; down-reason histogram ranks by count; injected eval
  results are honored.

**Verification**
- Full suite green: 516 tests, 0 failures (1 pre-existing skip). CI already runs the
  whole `PulseLoopTests` target via `clean test`, so the harness + report run on
  every PR with no workflow change needed.

Notes / decisions:
- The harness is deliberately deterministic (stubbed JSON, not a live client) so it
  doubles as a CI gate AND an in-app readout without a provider call or cost.

---

## 2026-06-24 — T5 Self-improving modules: improvement agent + safe apply pipeline (done)

Modules now get better on their own, safely: an agent proposes a better version as
a spec diff (never a live edit), and a guarded pipeline applies it.

**Diff + classification** (`Platform/SubAppSpecDiff.swift`)
- Pure `SubAppSpecDiff.between(old, new)` computes added/removed entities, fields,
  screens, type changes, newly-required fields, relabels, and schema-major changes.
- `isBreaking` is conservative: removing anything, changing a field type, a new or
  newly-required field, or a schema major bump is breaking; pure additive/relabel
  changes are non-breaking and data-preserving.

**Improvement agent** (`Platform/ModuleImprovementAgent.swift`)
- `ModuleImprovementAgent.propose(for:)` is deterministic + offline: self-heals an
  invalid installed spec, else proposes safe additive enhancements (a Notes field
  on entities that lack free text, an Overview dashboard when there's none). Always
  re-validates the proposal before offering it; bumps the version monotonically.
- `ModuleImprovementProposal` (Codable) carries the proposed spec, rationale, cached
  breaking flag, and a repair flag. `ModuleImprovementStore` persists at most one
  pending proposal per module + the user's `autoApplyNonBreaking` opt-in.

**Safe apply pipeline** (`Platform/ModuleImprovementApplier.swift`)
- `process(_:autoApplyNonBreaking:context:)` decides: re-validate → reject bad
  specs; require confirmation for breaking or when auto-apply is off; only
  auto-apply non-breaking + opted-in. `commit` persists the versioned spec
  (preserving origin), reloads the registry, migrates data, and stamps the new
  installed version via `SubAppRegistry.applyImprovedVersion`.
- `ModuleImprovementRunner.runIfDue(context:)` runs the agent across installed
  declarative modules at most once per local day; self-healing repairs and opted-in
  non-breaking changes auto-apply, everything else is staged.

**Surfaces**
- `PendingAction.Kind.applyModuleImprovement` + executor case (final-validate then
  `commit`), rendered as a standard Confirm card.
- New coach tool `improve_module` (in `PlatformControlTools`): proposes an
  improvement for a named user/installed module and stages an Apply card — never a
  live edit.
- `ModuleUpdatesView` gained a "Suggested improvements" section (auto-apply toggle,
  per-proposal Apply/Dismiss, breaking badge) and runs the daily agent on appear.

**Tests** (`ModuleImprovementT5Tests`, 11)
- Diff classification (additive vs remove/new-required); agent proposes a
  non-breaking enhancement / nothing when already complete / always-valid specs;
  pipeline requires confirmation when opted out, auto-applies when opted in, rejects
  uninstalled modules; runner stages for installed modules and is gated once/day.

**Verification**
- Full suite green: 516 tests, 0 failures (1 pre-existing skip).

Notes / decisions:
- The authoring heuristic is intentionally deterministic/offline so it's fully
  testable and can never silently break a module; an LLM author can plug into the
  same `propose(for:)` seam later with the safety pipeline unchanged.
- `SubAppSpecDiff` was tightened during testing: a brand-new REQUIRED field is now
  classified breaking (existing records would violate the new constraint), so it can
  never auto-apply.

---

## 2026-06-24 — T4 Always the best LLM: capability registry + smart routing (done)

Made model selection data-driven and transparent without touching the
reliability-anchor contract. Builds on the Sakana-style `AgentRouter` + `AIModel`
tiers + the T0 telemetry/feedback substrate.

**Capability registry** (`ModelCapability.swift`)
- Declarative `ModelCapability` per slug (tools? vision? reliable JSON? quality +
  cost class). `ModelRegistry` seeds a bundled table consistent with `AIModel.options`
  and the anchor/unreliable sets, exposes `candidates(for: role)` with hard
  constraints (generalist ⇒ tool+JSON-reliable, vision ⇒ multimodal), and is
  runtime-refreshable while never going empty.

**Feedback-weighted ranking** (`ModelRanking.swift`, pure)
- `ModelOutcomeStats` aggregates up/down votes, turns, recoveries, errors per model.
- `rank(...)` scores candidates = quality prior + smoothed satisfaction − recovery
  penalty − error penalty − cost, degrading to the prior alone with no signal (so
  day-one behavior is unchanged). `CoachFeedbackStore.outcomeStats(...)` joins
  telemetry + feedback on-device with no new schema.

**Smarter routing** (`AgentRouter`)
- New per-role "auto" mode (default on): `bestModel(for:stats:)` picks the top
  registry candidate, but an explicit user override always wins and the generalist's
  unreliable-JSON coercion is always applied last. `route(...)` role classification
  is unchanged. The orchestrator threads recent stats + an optional per-turn
  `forcedModel`.

**Transparency** (`CoachView`)
- A per-message `CoachRouteBadge` shows "<Role> · <model>" (with a recovery glyph)
  and a menu to re-run the turn on a different model in one tap, via
  `CoachViewModel.retry(...)`. A human-readable "why" line ("Reasoning task → best
  model: Nemotron 3 Super") is emitted into the live trace.

**Catalog refresh seam** (`ModelCatalogProvider.swift`)
- `OpenRouterModelCatalogProvider` over `HTTPTransport`, `isConfigured`-gated on
  `MODEL_CATALOG_BASE_URL`, parses OpenRouter `/models` (tools + image modalities),
  and is purely additive (no-op offline; conservative defaults so a refresh can't
  break the agent loop).

**Tests** (`ModelRoutingT4Tests`, 15) + updated `AgentRouterTests`
- Registry constraints; ranking (prior wins with no signal, strong feedback overrides
  a higher prior, deterministic, hasSignal); router (auto picks a candidate, override
  wins, generalist never unreliable-JSON, auto-off falls back, rationale text);
  catalog parser + merge-without-losing-bundled.

**Verification**
- iOS build green. Full suite green: 495 tests, 0 failures (1 pre-existing skip).

Notes / decisions:
- Kept `AIModel.jsonReliableAnchor` / `jsonUnreliableSlugs` / `toolIncompatibleSlugs`
  authoritative; routing reads the registry for selection but the anchor coercion is
  the final word for the generalist. Stats are model-level (not yet role-scoped in
  the live path) which is a sufficient signal for v1.

---

## 2026-06-24 — T3 Sharing & the community module gallery (done)

Made the "super-app" unlock real: modules can be shared as signed portable bundles
and installed from a community gallery, safely. Built on the existing F1/F2 seams
(`SubAppPackager` HMAC sign/verify, `SubAppModerator`, `ImportReviewSheet`,
`SubAppRegistryView`) rather than a parallel stack.

**Community gallery over a network seam** (`ModuleGalleryProvider.swift`)
- New `HTTPModuleGalleryProvider: SubAppRegistryService` pulls a JSON catalog over
  the testable `HTTPTransport`, `isConfigured`-gated on `MODULE_GALLERY_BASE_URL`
  (Info.plist `REPLACE_WITH_YOUR_*` placeholder), and degrades to the bundled
  curated catalog when unconfigured, on 5xx, or on transport error so browse/search
  always works offline.
- Pure `parseCatalog(_:)` decodes each entry, then re-decodes + verifies the package
  signature + validates the spec; any tampered or malformed module is dropped before
  it can reach the install flow. Drops straight into the existing
  `SubAppRegistryView` (no UI churn).

**Richer listings**
- `RegistryListing` now carries `installCount` + per-version `changelog`
  (`SubAppChangelogEntry`) for an informed install decision.

**Real attribution + trust**
- `UserSubAppStore` records an origin per saved spec; gallery installs and file
  imports are now persisted as `.installed` (not `.userCreated`), and
  `loadUserSpecs` honors it. `uninstall_subapp` accepts `.installed` modules too.
  Legacy entries default to `.userCreated`.

**Tests** (`ModuleGalleryTests`, 10)
- Parser returns verified listings (incl. category/installs/changelog); drops a
  tampered package; throws on garbage. Provider: unconfigured → bundled fallback,
  configured → live catalog, 5xx → fallback, transport error → fallback, search
  request carries `q`. Origin: gallery install tracked as `.installed`, builder save
  defaults to `.userCreated`.

**Verification**
- iOS build green. Gallery suite green: 10 tests, 0 failures.

Notes / decisions:
- Kept the existing `SubAppRegistryService` protocol as the seam (the HTTP provider
  conforms to it) so the gallery view needed zero changes. Installed modules remain
  declarative specs only — never code — which the consent sheets state.

---

## 2026-06-24 — T2 "Describe it and it exists": conversational module builder (done)

Lowered module creation from "use the builder screen" to "just say it" right in
the Coach (typed or by voice), with a live preview and an explicit Install
confirm step before anything is created. Built on the existing
`generate_subapp_spec` / `refine_subapp_spec` / `SubAppSpecValidator` /
`SubAppRuntimeView` seams — no parallel builder.

**Build by talking → preview → confirm → install + open**
- `save_subapp` no longer installs immediately. It re-validates + guardrail-checks
  the staged draft and queues a new `PendingAction(.installSubApp)` confirm card,
  returning `needs_confirmation`. The draft stays staged so the card can preview it.
- New `CoachInstallCardView` (on-design): a "NEW MODULE" card showing the module's
  name, summary, per-entity field list, a permissions row when requested, and a
  **Live preview** that opens `SubAppRuntimeView` (in-memory store) in a sheet, with
  Cancel / Install (accent) buttons. Rendered by `CoachBubble` for `.installSubApp`
  actions; all other pending actions keep the plain `CoachActionCardView`.
- `PendingActionExecutor.installSubApp` commits on Confirm: final validate +
  guardrail gate, `UserSubAppStore.save` → `loadUserSpecs` → `install`, clears the
  draft, and requests navigation to the freshly installed module via the new
  `AppRoute.subApp(id)` (wired into `RootViews` → `SpecSubAppHost`).

**Iterate by conversation**
- `refine_subapp_spec` now stamps a bumped version on each edit via the pure
  `SubAppBuilderTools.bumpedVersion(for:isRefinement:)` (patch bump over the highest
  of the staged draft / installed module of the same id; fresh generations never
  bump), and re-validates the full updated spec before re-staging.

**Quality gate**
- Neither generation, refinement, nor save will stage/install a spec that fails
  `SubAppSpecValidator` or `SubAppGuardrails`. The tools return the concrete issues
  (path + message / blocker text) so the model can fix them (valid slug id, SF
  Symbol icon, fewer fields…) instead of dead-ending the user. Prompt updated with a
  "Build a module by talking" rule describing the design → refine → preview-install
  flow and the fix-the-issues expectation.

**Tests** (`ConversationalBuilderTests`, 7)
- Generate stages a validated draft; refine bumps version + re-validates; pure
  version bump is monotonic and never fires on fresh generation; invalid spec
  (emoji icon) is rejected with an actionable error and never staged; `save_subapp`
  queues an `installSubApp` confirmation without installing and keeps the draft;
  no-draft save errors; confirming the install actually installs, clears the draft,
  and requests opening the module.

**Verification**
- iOS build green. Full suite green: 470 tests, 0 failures (1 pre-existing skip).
- Installed + launched on the iPhone 17 Pro simulator.

Notes / decisions:
- Reused the `PendingAction` + confirm-card mechanism rather than inventing a new
  card path: an install is a consequential write, which is exactly what that seam is
  for. The dedicated install card adds the preview affordance the generic card lacks.
- The standalone `SubAppBuilderView` (with its own preview + permission sheet) is
  unchanged; the new in-chat flow is the additive, voice-reachable path.

---


Made hands-free voice the headline surface: one breath in, a whole life-admin
batch out, then a spoken multi-part confirmation. Built entirely on the existing
`VoiceSessionController` + Coach pipeline, so the model/tool layer is unchanged.

**Multi-intent fan-out + confirmation**
- Prompt: added an explicit MULTI-INTENT rule in `CoachPromptBuilder` — a single
  (often spoken) message can bundle several unrelated requests across modules; the
  model must act on ALL of them in one turn and put one short past-tense entry per
  action in `actions_taken` (which is what gets read back), keeping `summary` to a
  single sentence.
- `VoiceSessionController.spokenSummary` is now pure/static and builds a natural
  read-back: "Done: logged a 30 minute run, added eggs to breakfast, and set a
  reminder to call mom at 6 PM. <summary>." Serial "and", de-duped, and it drops a
  summary that merely echoes a lone action.

**Proactive daily brief (opt-in)**
- New pure `VoiceBriefComposer`: time-aware greeting + the top one/two durable
  `DailyLearning` items by importance + a soft "what first?" prompt, de-dashed
  through the same `CoachResponse.deDash` rule. Once-per-day gate via a stable
  local `yyyy-MM-dd` key.
- `VoicePreferences` gained `voiceBriefEnabled` (off by default) and
  `voiceBriefLastDay`. `VoiceSessionController.start()` speaks the brief before the
  first listen when due (tick loop hands off to listening when TTS ends) and emits
  a content-free `voice_brief_spoken` event.
- Settings: a "Spoken daily brief" `ComfortToggleRow` added to the Voice section.

**Barge-in / correction**
- Tapping the orb while it's speaking already stops TTS and starts listening; the
  speaking caption now invites it ("Speaking… tap to jump in"). Did NOT add
  mic-level auto-barge-in: the mic is closed during TTS so its level is stale, and
  opening it would risk echo/feedback for no reliable gain.

**Modern, on-feel animations**
- `VoiceOrb` reworked: spring-driven core/rings reacting to live level, a calm
  idle breath, an orbiting "thinking" dot, and a steady speaking pulse.
- New `VoiceWaveform`: a `TimelineView`-driven equalizer strip with a bell
  envelope and per-bar ripple, scaled by mic level, shown while listening.
- Turn cards animate in (move+fade) with a spring scroll-to-bottom.
- The voice surface keeps its intentional dark immersive treatment (a deliberate,
  already-shipped departure from the white "calm" system); accents and motion were
  modernized rather than redesigning the whole surface.

**Tests** (`VoiceOrganizeTests`, 12)
- Multi-part confirmation: serial-and join, two-item "and", summary-echo dedupe,
  summary fallback, nil response, proper-noun casing.
- Brief: greeting by time of day, top-by-importance selection, de-dashing, empty
  invite, opt-in/day gating, stable day key.

**Verification**
- iOS build green. Full suite green: 463 tests, 0 failures (1 pre-existing skip).
- Installed + launched on the iPhone 17 Pro simulator.

Notes / decisions:
- All new spoken/printed text routes through `deDash`, so the no-em-dash rule holds
  for voice too. Brief and confirmation logic are pure and unit-locked.

---

## 2026-06-24 — T0 Foundations: feedback + decision logging (done)

Shipped the signal layer everything else in the loop learns from.

**Reply feedback**
- New `CoachFeedback` SwiftData model (message id, conversation id, rating up/down,
  low-cardinality reason code, plus a role/model snapshot copied from the turn's
  decision log). Registered in `ModelContainerFactory.coreModels`.
- `CoachFeedbackStore` (pure, `@MainActor`): record/update + fetch. Re-rating a
  message updates the existing row in place (no duplicates) and snapshots the
  role/model from `TurnTelemetry`. Emits a content-free `coach_feedback` analytics
  event through the existing opt-in `Analytics`/`Telemetry` seam.
- `CoachFeedbackBar` on-design view under each structured assistant reply: thumbs
  up/down (SF Symbols, muted tones, no accent fills), and a down vote reveals
  reason chips (Inaccurate / Too long / Off topic / Didn't do it). Reflects any
  prior rating on appear. Wired into `CoachBubble` in `CoachView`.

**Decision log**
- New `TurnTelemetry` SwiftData model: one row per LLM turn — role label, resolved
  model, tool rounds, de-duped tool names (no args), input/output tokens, latency,
  recovered-on-anchor flag, error reason. Content-free. Registered in the container.
- `CoachOrchestrator.TurnResult` extended with `roleLabel`, `model`, `rounds`,
  `recovered`; `finalAnswer` now reports whether it recovered on the reliability
  anchor (returns `(answer, recovered)`), and `runOpenAI` populates the new fields
  (model reflects the anchor when recovery happened).
- `CoachViewModel` measures per-turn latency and writes exactly one `TurnTelemetry`
  row per LLM turn via the pure, testable `CoachViewModel.makeTelemetry(...)`, plus a
  content-free `coach_turn_completed` event.

**Tests** (`CoachFeedbackTelemetryTests`, 5)
- Feedback round-trips; re-rating updates in place (no duplicate); feedback snapshots
  role/model from telemetry; `makeTelemetry` captures all decision fields with
  de-duped/ordered tool names; error reason recorded for failed turns.

**Verification**
- iOS build green. Full suite green: 451 tests, 0 failures (1 pre-existing skip).
- Installed + launched on the iPhone 17 Pro simulator.

Notes / decisions:
- Telemetry rows are written only for real LLM turns (scripted fallbacks carry no
  routing decision). Both feedback and telemetry are on-device and content-free; the
  `Analytics` events are no-ops unless the user has opted into diagnostics.
- These two tables are the join-free substrate for T4 (feedback-weighted routing) and
  T6 (quality dashboard).
