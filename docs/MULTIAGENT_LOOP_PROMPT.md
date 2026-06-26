# Open-Loop Prompt — "Multi-Agent Router: route every turn to the best specialist model"

> Paste this whole file to the agent as the brief. Work it as a continuous loop:
> one track at a time, smallest shippable change, **keep the iOS build + full test
> suite green every iteration**, append a dated entry to
> `docs/MULTIAGENT_PROGRESS.md`, and run on the simulator at the end. Do **not**
> stop until every track is done and acceptance is met.
>
> You are the founder of Sakana AI. One generalist model answering every prompt is
> a dead end — nature wins with **collections of specialists**. Turn the single-model
> assistant into a **router-based multi-agent system**: a fast classifier picks the
> best specialist "agent" (a role + model + tuned hint) for each turn, the existing
> agent loop runs on that model, and the routing decision is **shown live in the
> trace**. Keep it at ~1x cost/latency (route, don't ensemble) and never regress the
> hard-won structured-JSON reliability.

---

## NON-NEGOTIABLE: Follow the app design system

Every view, sheet, row, button, chip, trace label, and empty state you add or touch
MUST follow `.cursor/rules/design-system.mdc`. A feature is NOT done if it violates
the design system. Key rules:

- **No emoji anywhere in rendered UI** (including trace labels). Use
  `Image(systemName:)` SF Symbols only.
- **Colors via `PulseColors.*`** tokens only. Accent is for rare emphasis.
- **Primary buttons = `Color.black` fill, white text**; secondary = outlined with
  `borderStrong`. Never accent-filled buttons.
- **Typography via `PulseFont.*`**; section labels UPPERCASED + tracked + muted.
- **Cards**: 16–20px padding, 14–16px radius, 1pt `borderHairline`. Reuse
  `pulseCardSurface()` / `PulseCard`.
- **Sheets**: `.presentationDetents`, `.presentationDragIndicator(.visible)`,
  `PulseColors.background` bg, left-aligned bold 22pt title.

Reuse the existing AI-settings UI vocabulary (the `AIModel` picker rows in
`SettingsView`/`CoachSettingsSection`) — match it, don't invent a parallel style.

---

## ROLE & NORTH STAR

The chat should behave like a **team of specialists with a smart dispatcher**, not a
lone generalist:

1. **Classify** — a fast, deterministic router reads the turn (text, attachments,
   recent context) and picks a role.
2. **Dispatch** — the turn runs on that role's specialist model via the
   orchestrator's existing `modelOverride` seam. One model per turn (route, not
   ensemble) so cost/latency stay ~1x.
3. **Show the work** — the trace surfaces the chosen agent + model
   ("Routing to Strategist · Nemotron") so it feels like a real multi-agent system.
4. **Stay reliable** — the generalist (`openai/gpt-4o-mini`) is the safe default for
   tool + structured-JSON turns; specialists are used where they win; the existing
   `parseFinal` repair + meta-apology guard remain the safety net; any specialist
   parse failure falls back to the generalist.

---

## THE ROSTER (router targets)

- **Generalist** — `openai/gpt-4o-mini`. Default. Chat, tool calling, reliable JSON.
  Anything ambiguous routes here.
- **Strategist** — best **Nemotron** (e.g. `nvidia/nemotron-3-super-120b-a12b`).
  Planning / deep reasoning. Nemotron needs `detailed thinking on` to reason and can
  leak thinking tokens into content — handle that so the final stays a single JSON
  object.
- **Researcher** — **MiniMax** (long-context, multi-search synthesis). Heavy web
  research / many-source turns.
- **Vision** — the existing vision tier. Photo/label turns (path already exists; keep
  it forcing the multimodal model).

Pick the best currently-available Nemotron + MiniMax slugs on OpenRouter during T0
and record them in `docs/MULTIAGENT_PROGRESS.md`. Only list models that actually
support function/tool calling (the agent loop depends on it).

---

## OPEN LOOP — TRACKS (do in order; one PR-sized change each)

### T0 — Roster: add specialist models
- Verify, live on OpenRouter, the best Nemotron + MiniMax slugs that support
  **tools + `response_format`/structured output**. Note tool/JSON reliability per
  model in the progress doc.
- Add them as `AIModelOption`s in `PulseLoop/Services/AIModel.swift` (smart +
  reasoning tiers as appropriate). Do **not** change the smart-tier default away from
  `openai/gpt-4o-mini` (reliability anchor).
- Tests: existing `AIModel` expectations stay green; add a test asserting the new
  slugs are present and not in `toolIncompatibleSlugs`.

### T1 — AgentRouter (pure, unit-tested)
- New `PulseLoop/Coach/Orchestration/AgentRouter.swift`: an `AgentRole` enum
  (`generalist`, `strategist`, `researcher`, `vision`) each carrying `{modelSlug,
  label, promptHint}`, and a pure `route(userText:hasImage:recentMessages:) ->
  AgentRole` function.
- Heuristic-first (no extra LLM call → ~1x latency): photo ⇒ vision; planning/
  reasoning keywords ("plan", "strategy", "compare", "why", "analyze", "step by
  step", long multi-part asks) ⇒ strategist; research/"latest"/"find sources"/
  multi-entity lookups ⇒ researcher; everything else ⇒ generalist (safe default).
- Resolve each role's slug through `AIModel` (so user overrides + tool-capable
  coercion still apply); generalist = `AIModel.smart.toolCapableResolvedSlug`.
- Tests: representative prompts map to the expected role; ambiguous ⇒ generalist;
  photo ⇒ vision regardless of text.

### T2 — Wire the router into the turn
- In `CoachViewModel`/`CoachOrchestrator.runTurn`, consult `AgentRouter` to compute
  the per-turn `modelOverride` and an optional role `promptHint`. Pass the override
  into the existing `send(...)` path (it already takes `modelOverride`).
- Photo turns keep forcing the vision model (current behavior) — the router returns
  `.vision` for them, so this stays consistent.
- Respect a routing on/off switch (T5): when off, behave exactly as today
  (generalist only).
- Tests: orchestrator turn with a stubbed client records the routed slug; routing
  off ⇒ uses `flags.model`.

### T3 — Nemotron / specialist safety
- When routed to a reasoning specialist that needs it (Nemotron), prepend
  `detailed thinking on` to the system message, and make sure thinking/reasoning
  tokens are **segregated from the final JSON** (extend `parseFinal` /
  `CoachResponseParser` so leaked `<think>`-style or pre-amble reasoning is stripped
  before parsing).
- On repeated parse failure for a specialist, **fall back to the generalist**
  (`openai/gpt-4o-mini`) for that turn rather than surfacing a fallback card.
- Tests: a stubbed Nemotron-style reply with leading reasoning still parses to a
  clean `CoachResponse`; specialist parse failure triggers a generalist retry.

### T4 — Visible trace (multi-agent feel)
- At turn start (after routing, before the first model call), emit a
  `CoachTraceEvent` like `"Routing to Strategist · Nemotron"` (status `.thinking`).
- Render the routed agent + model in the trace strip
  (`CoachTraceStrip`/`CoachView`) — on-design, no emoji, SF Symbol per role.
- Tests/build: the event is emitted with the chosen role/model; view builds.

### T5 — Settings (multi-agent routing controls)
- Add a "Multi-agent routing" toggle (default **ON**) and per-role model pickers in
  the AI Assistant settings, reusing the existing `AIModel` picker rows. Persist via
  `CoachSettings`/`UserDefaults` like the other model selections.
- When off, the assistant uses the generalist only (T2 honors this).
- On-design (picker rows, muted section header, design-system styling).
- Tests: toggle + per-role selection round-trip; default ON.

### T6 — Prompt: role hints
- Update `CoachPromptBuilder` so the role `promptHint` shapes tone/depth
  (Strategist = plan-first, rigorous; Researcher = search-heavy, cite everything;
  Generalist = concise, helpful) **without** weakening the strict single-JSON output
  contract. The hint augments, never replaces, the existing system prompt.
- Tests: prompt includes the hint when a non-generalist role is active.

### T7 — Verify end-to-end
- Run on the simulator. Confirm:
  - A reasoning/planning prompt ("Plan a 3-day strategy to…") routes to **Nemotron**
    and returns a clean structured answer (no JSON-apology regression).
  - A normal chat/tool prompt stays on **GPT-4o-mini**.
  - The trace shows the routed agent + model.
- Full test suite green.

---

## TOOLS & FILES YOU'LL TOUCH (grounding)

- Model/role selection: `PulseLoop/Services/AIModel.swift`,
  `PulseLoop/Coach/Config/CoachFeatureFlags.swift` (`model:97`),
  `PulseLoop/Coach/Config/CoachSettings.swift`.
- Orchestration loop + `send(modelOverride:)`:
  `PulseLoop/Coach/Orchestration/CoachOrchestrator.swift` (`send` at `:270`,
  `parseFinal` at `:216`), new `AgentRouter.swift` alongside it.
- Turn entry: `PulseLoop/Coach/ViewModels/CoachViewModel.swift`.
- Trace: `PulseLoop/Coach/ViewModels/CoachTraceEvent.swift`,
  trace strip in `PulseLoop/Views/CoachView.swift`.
- Parser/repair: `PulseLoop/Coach/Schema/CoachResponseParser.swift`.
- Prompt: `PulseLoop/Coach/Context/CoachPromptBuilder.swift`.
- Settings UI: `PulseLoop/Views/SettingsView.swift` /
  `PulseLoop/Coach/Config/CoachSettingsSection.swift`.

---

## HARD ACCEPTANCE (the whole loop)

- [ ] iOS builds green; full test suite green every iteration.
- [ ] `AgentRouter` is pure + unit-tested (intent → role, ambiguous → generalist,
      photo → vision, Nemotron reasoning-token handling).
- [ ] Each turn shows its routed agent + model in the trace; no emoji;
      PulseColors/PulseFont, design-system sheets.
- [ ] Reasoning/planning turns route to **Nemotron**; chat/tool/JSON turns stay on
      **GPT-4o-mini**; vision turns unchanged.
- [ ] Specialist parse failures fall back to the generalist — the JSON-apology bug
      stays fixed.
- [ ] Multi-agent routing is user-toggleable (default ON) with per-role model
      pickers; off ⇒ generalist-only, exactly as today.
- [ ] App runs on the simulator with the new routing.

---

## WORKING AGREEMENT

- One track per iteration, smallest shippable change, build + tests green before
  moving on. Append a dated line to `docs/MULTIAGENT_PROGRESS.md` each time.
- Route, don't ensemble — ~1x cost/latency. Reuse the existing `modelOverride`,
  trace, and `AIModel` seams instead of inventing parallel ones.
- Generalist (`openai/gpt-4o-mini`) is the reliability anchor and the safe default
  for anything ambiguous or when routing is off.
- Follow `.cursor/rules/design-system.mdc` for every pixel.
- Do not stop until all tracks are done and acceptance is met.
