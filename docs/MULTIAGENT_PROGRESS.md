# Multi-Agent Router — Progress

Dated log of the multi-agent routing loop (see `docs/MULTIAGENT_LOOP_PROMPT.md`).
Route, don't ensemble: each turn is classified and dispatched to the best specialist
model, with the routing decision shown in the trace. Generalist
(`openai/gpt-4o-mini`) is the reliability anchor and safe default.

## 2026-06-24 — T0 Roster + T1 AgentRouter
- T0: Verified on OpenRouter that `nvidia/nemotron-3-super-120b-a12b` (Strategist) and
  `minimax/minimax-m2` (Researcher, 205K ctx) both support `tools` + `response_format`.
  Added both as selectable `AIModelOption`s (smart tier; Nemotron also in reasoning tier)
  in `PulseLoop/Services/AIModel.swift`. Smart-tier default stays `openai/gpt-4o-mini`.
- T1: Added pure `AgentRouter` + `AgentRole` (`PulseLoop/Coach/Orchestration/AgentRouter.swift`):
  heuristic-first classifier (photo → vision; research keywords → researcher; reasoning/
  planning/long multi-part → strategist; else generalist). Per-role slug resolution with
  user overrides; routing master toggle (default ON). Unit-tested in `AgentRouterTests`.
- Build green.

## 2026-06-24 — T2 wire + T3 safety + T6 prompt hint
- T2: `CoachOrchestrator.runOpenAI` now routes each turn via `AgentRouter`, sets the
  per-turn `modelOverride` (vision turns still force the multimodal slug), threads the
  role `promptHint` into the system prompt, and prepends `detailed thinking on` for
  reasoning specialists. Emits a "Routing to <Role> · <Model>" trace event.
- T6: `CoachPromptBuilder.systemPrompt` gained a `roleHint` parameter appended to the
  base prompt (augments, never replaces; preserves the single-JSON contract).
- T3: `CoachResponseParser.stripReasoningTokens` strips `<think>/<reasoning>/<thinking>/
  <thought>` blocks (and dangling close tags) so leaked chain-of-thought never breaks
  JSON extraction. `parseFinal` now returns nil on exhaustion; new `finalAnswer` wrapper
  retries the final on the generalist (gpt-4o-mini) when a specialist can't deliver,
  before any canned fallback — keeping the JSON-apology bug fixed.
- 17 AgentRouterTests pass (roster, routing, overrides, reasoning-token stripping).
  Build green.

## 2026-06-24 — T4 trace + T5 settings + full suite green
- T4: `CoachTraceStrip` now renders the routed agent with its role SF Symbol for the
  "Routing to <Role> · <Model>" step (e.g. brain for Strategist), and marks passed
  phase steps done so the routing row doesn't spin. Design-system compliant, no emoji.
- T5: New `MultiAgentSettingsSection` in Settings — a "Route to specialist models"
  toggle (default ON, persisted to `agentRouting.enabled`) plus per-role model pickers
  (Strategist/Researcher) reusing the existing `AIModel.smart` picker rows, persisted to
  `agentRole.*`. Off ⇒ generalist-only.
- Note: a brief `git stash`/`pop` round-trip during testing temporarily reverted tracked
  files; recovered cleanly, no work lost.
- Aligned the stale `testUnparseableFinalFallsBack` with the prose-salvage behavior
  (empty output → fallback; real prose → salvaged) and added `testProseFinalIsSalvaged`.
- Full suite green: 414 tests, 0 failures.

## 2026-06-24 — T7 Verify (loop complete)
- Final build green; full suite green (414 tests, 0 failures, 1 skipped).
- Installed + launched on the iPhone 17 Pro simulator (iOS 26.5); app runs stably with
  multi-agent routing wired into every chat turn.
- Routing verified via unit tests + live wiring: reasoning/planning → Strategist
  (Nemotron), live-research → Researcher (MiniMax M2), photos → Vision, everything else
  + ambiguous → Generalist (GPT-4o-mini, the reliability anchor). Specialist parse
  failures hand off to the generalist; reasoning tokens are stripped before JSON parse,
  so the JSON-apology bug stays fixed. The trace shows "Routing to <Role> · <Model>".
- All tracks T0–T7 done; acceptance met.





