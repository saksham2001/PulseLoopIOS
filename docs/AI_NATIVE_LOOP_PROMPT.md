# PulseLoop → Most Intuitive, AI-Native Modular App — Loop Prompt

> **How to use this file.** Paste the section titled **"THE LOOP PROMPT"** into the agent as a single message at the start of each working session. The agent picks one iteration from the backlog, does it end-to-end, updates the tracker `docs/AI_NATIVE_PROGRESS.md`, verifies, and stops. Re-run to advance. Everything above the loop prompt is reference the prompt points at — keep it in the repo.

---

## 0. North-Star Vision (fixed mission — never changes)

Make PulseLoop the **most intuitive, AI-native modular life-OS** on either platform (iOS + web). "AI-native" means: the assistant is the primary surface, it **streams**, it is **transparent about what it does**, it **takes real action** across every installed module, it **stays on the user's topic** (universal personal assistant — travel, tasks, planning, errands, finance, learning, work, AND health — never circling back to health unprompted), and it has **unlimited web search** to find real-world answers (flights, hotels, events, products) and turn them into saved, organized records.

"Intuitive" means: zero dead ends, every action discoverable, every destructive action confirmable and reversible, every AI step visible, and the module system (enable/disable) instantly reshapes nav, Home, suggestions, and the AI's capabilities — on both iOS and web.

**Non-negotiables across every iteration:**
- The app must **always build and run** at the end of each iteration. iOS: `xcodebuild … BUILD SUCCEEDED`. Web: `npm run lint` + `npm run build` clean. Never leave `main` broken.
- **Design system is law** (iOS `App/AppTheme.swift` + `DesignSystem/Components.swift` + `.cursor/rules/design-system.mdc`; web `web/src/lib/tokens.ts` + `globals.css` + `components/ui.tsx`). SF Symbols only on iOS, design tokens only on web. No new colors. Primary buttons black, not accent.
- **No silent failure, no silent data loss.** Every AI error is surfaced to the user; every queued action is honored.
- **Topic discipline holds.** Health stays one domain among many; never steer back to rings/HR/sleep unless the user's request is genuinely about their body.
- **Destructive actions confirm.** Every delete/cancel/archive routes through the confirm-card / pending-action pattern consistently across all modules and tools.
- **Backward-compatible data.** SwiftData migrations additive; web migrations additive. Never drop user data.

---

## 1. Codebase Anchors (real — do not invent file names)

**iOS Coach (the agent):**
- Orchestrator / agent loop: `PulseLoop/Coach/Orchestration/CoachOrchestrator.swift` (rounds, tool budget, retries, traces, `previousResponseId`).
- View model: `PulseLoop/Coach/CoachViewModel.swift` (persists messages, `errorBanner`, credit handling, `makeClient`).
- Chat UI: `PulseLoop/Views/CoachView.swift`, `ModuleAwareChat.swift`, `CoachResponseView.swift`, `CoachActionCardView.swift`, trace strip in `CoachView.swift`.
- System prompt (already general-purpose, has TOPIC DISCIPLINE block): `Coach/Context/CoachPromptBuilder.swift`.
- Tools: `Coach/Tools/*Tools.swift`; registry `Coach/Tools/ToolRegistry.swift`; dispatch `Coach/Orchestration/ToolCallExecutor.swift`; tool shape `Coach/Tools/CoachTool.swift`.
- Web search (hosted, ON by default): `Coach/Tools/WebSearchTool.swift`, flag `Coach/Config/CoachFeatureFlags.swift` → `CoachSettings.enableWebSearch`.
- Confirm cards: `Coach/Orchestration/PendingAction.swift`, `PendingActionExecutor.swift`; rendered in `CoachActionCardView` (`CoachView.swift`).
- Persisted tool trace: `CoachToolCall` (written in `CoachViewModel.swift`, currently NOT read back by any view).

**iOS Modules / Sub-Apps:**
- Registry: `PulseLoop/Platform/SubAppRegistry.swift`; protocol `Platform/SubApp.swift`; conformers `Platform/SubApps/*SubApp.swift`.
- Module enum: `App/AppTheme.swift` `enum AppModule` (incl. `.travel`). Schema: `Persistence/ModelContainerFactory.swift`.
- Travel: `Models/TravelModels.swift` (`Trip`, `TripItem`), `Views/TravelView.swift` + `TripDetailView`, tools `Coach/Tools/TravelTools.swift`, nav map in `PlatformControlTools.swift` (`navigate_to`).

**Web (Next.js):** `web/src/app/(workspace)/*` screens, shell `web/src/components/workspace/*`, coach endpoint `web/src/app/api/v1/coach/web`, settings `/api/settings`, records `/api/records`.

---

## 2. Known issues found in review (the seed backlog — fix these, in order)

**Bugs (silent failure / data loss — fix first):**
- **BUG-1** Only the first pending confirmation survives a turn. `CoachViewModel` persists `result.pendingActions.first?.encodedJSON()`; 2nd+ destructive actions are dropped and never execute, with no indication. Persist + render ALL pending actions for a message.
- **BUG-2** `CoachViewModel.errorBanner` is set on transport failures but never displayed in `CoachView`; generic failures show only a canned fallback bubble. Surface a visible, dismissible error state in chat.
- **BUG-3** Destructive Travel ops apply instantly with no confirm card — `delete_trip_item` hard-deletes, `update_trip(status:'cancelled')` archives a whole trip. Route them through the same `PendingAction` confirm-card UX as tasks/notes/modules.

**AI-native gaps (highest perceived impact):**
- **AIN-1** No token streaming — replies land all at once. Add streaming so partial text renders as it arrives.
- **AIN-2** The detailed tool trace is persisted (`CoachToolCall`) but never shown after a turn. Render a collapsible "what I did" (searched web → created trip → added items) under each finished assistant reply.
- **AIN-3** Travel turns can't deep-link: after `create_trip` the AI cannot open the trip (no `tripDetail` destination / `trip_id` in `navigate_to`). Add a `trip_id`-aware navigation so the AI can take the user straight to the created trip.
- **AIN-4** Trip itinerary groups by kind, not day; no map. Add a day-by-day timeline and a MapKit overview in `TripDetailView`.
- **AIN-5** Two competing chip rows (cold-start module chips + structured follow-up chips) after every reply. Show one coherent suggestion row; make chips surface action capabilities (plan trip, create task, navigate), not just read-only questions.
- **AIN-6** No stop/cancel button for an in-flight multi-round turn. Add cancel.
- **AIN-7** Header shows `AIModel.smart` regardless of the provider actually used. Reflect the real client/model.
- **AIN-8** Greeting/suggestions adapt to modules but not to time-of-day or recent activity. Make the empty state context-aware.

Add new findings to the tracker as you discover them; keep them ordered by user impact.

---

## 3. Definition of Done (per iteration)
- The targeted bug/gap is fully resolved (not partially) and demonstrably works.
- Matches the design system; correct in light + dark (web) / light + dark (iOS).
- Backed by real data + tools; mutations persist; no silent failure or dropped action.
- iOS `BUILD SUCCEEDED`; web `npm run lint` + `npm run build` clean; no console errors.
- No regressions to completed items. Tracker updated with status + a one-line verification note.

## 4. Guardrails
- Don't refactor unrelated code. Don't add dependencies without noting why (MapKit is system, fine).
- If a data-model or product decision is genuinely ambiguous, make the reasonable choice, mark it `// DECISION:` in code + the tracker, and keep going. Only stop for irreversible/destructive ambiguity.
- Keep iterations small and shippable; never batch unrelated changes into one iteration.

---

## 5. THE LOOP PROMPT (paste this each session)

```
You are continuing a long-running project to make PulseLoop the most intuitive,
AI-native modular life-OS on iOS + web. Read docs/AI_NATIVE_LOOP_PROMPT.md (vision,
anchors, backlog, Definition of Done, guardrails) and docs/AI_NATIVE_PROGRESS.md
(current status). Then:

1. Pick the next unfinished item from the backlog in AI_NATIVE_PROGRESS.md
   (bugs BUG-1..3 first, then AIN-1.. in order). Do exactly ONE item this pass.
2. Read the matching files (the anchors in section 1). Note data, states, interactions.
3. Plan the change in 2-4 sentences.
4. Build it using existing design tokens/primitives and the established tool/confirm-card
   patterns. Wire to real data — never mock silently.
5. Verify: iOS build SUCCEEDED and/or web lint+build clean; the interaction works in
   light + dark; state persists; topic discipline + no-silent-failure hold.
6. Self-review against the Definition of Done. If it fails, fix and re-verify this pass.
7. Update docs/AI_NATIVE_PROGRESS.md: check the item, add a one-line verification note,
   and append any new findings to the backlog.

Continue the loop without waiting for me unless you hit an irreversible/destructive
ambiguity. After each item, report: what you built, verification results, next item.
```
