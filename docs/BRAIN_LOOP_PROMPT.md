# PulseLoop → "Ultimate Brain" Coach + AI-First Notes — Loop Prompt

> **How to use this file.** Paste the section titled **"THE LOOP PROMPT"** (§4) into Claude (Cursor agent) as a single message at the start of each working session. Claude does exactly one iteration, updates the tracker `docs/BRAIN_PROGRESS.md`, and stops. Re-run to advance. The rest of this document (Context, Roadmap, Guardrails) is reference the prompt points Claude at — keep it in the repo.

---

## 0. North-Star Vision (the fixed mission — never changes between iterations)

Make the **AI Coach chatbox the ultimate brain of PulseLoop**: a single conversational surface that can **read, analyze, create, edit, and delete across every module and feature** in the app, manage the platform itself (modules, sub-apps, settings, navigation), and act safely. In parallel, make the **Notes feature AI-first**: capture, drafting, editing, organization, and search are all driven by the AI by default, with manual block editing as the fallback rather than the primary flow.

**Two pillars:**

1. **Ultimate Brain.** The Coach already reads ring/health data, charts, analyzes, and has narrow writes (goals, memory, activity sessions, tasks/notes create-only, module enable/disable, sub-app install/uninstall, media). The mission is to give it **complete, symmetric CRUD over every SwiftData-backed module** (read + create + update + delete + complete/toggle where relevant), plus **navigation** and **profile writes**, and to **teach the model these capabilities in the system prompt** so they are actually used. The brain should be able to answer "what's on my plate today across tasks, protocol, day plan, and habits?" and act: "move my Thursday workout to Saturday, mark the morning stack logged, and add a note about my knee."

2. **AI-First Notes.** Today notes open to a blank block editor; AI is buried in a menu and one-shot. Make capture (text + voice) route through the `CapturePlan` pipeline by default, add **conversational in-note editing** (streaming), **semantic search** across content, real **tags + collections** on the model, and **note↔task linkage**, so the note "understands itself" and the user mostly talks to it.

**Non-negotiables across every iteration:**
- The app must **always build and run** at the end of each iteration. Never leave the working tree broken.
- **Design system is law.** Every screen uses `PulseColors` / `PulseFont` / `PulseRadius` / `PulseLayout` and components from `App/AppTheme.swift` + `DesignSystem/Components.swift`. Follow `.cursor/rules/design-system.mdc`. **SF Symbols only, no emoji in rendered UI. Primary buttons are black, accent used sparingly.**
- **Every destructive or risky write goes through the `PendingAction` confirm-card flow** (delete, bulk edit, disabling/uninstalling modules). Reversible writes apply immediately.
- **Backward-compatible data.** SwiftData migrations are additive/lightweight (defaulted optional fields, tolerant decoders). Never drop user data.
- **No secrets in source.** AI keys stay in Keychain. The legacy plaintext OpenRouter key in `Services/AIService.swift` must not spread; prefer the Coach orchestrator for new AI work.
- **Tools are deterministic + safe.** Tool handlers read/write through the existing data layer, validate inputs, and return structured `ToolResult`. No arbitrary code execution.

---

## 1. Codebase Context (real anchors — verified; do not invent file names)

**Stack:** SwiftUI + SwiftData. Entry `PulseLoop/PulseLoopApp.swift` → `RootAppView` (`Views/RootViews.swift`). The Coach chatbox is `Views/CoachView.swift` (presented full-screen via `.fullScreenCover` from the center bar button in `RootViews.swift` and from `HomeView.swift`).

**Coach orchestrator (the brain's engine):**
- Agent loop: `Coach/Orchestration/CoachOrchestrator.swift` (rounds, tool budget, retries, traces, `previousResponseId`). Tool budget/rounds from `CoachFeatureFlags` (`maxToolCalls`=8, `maxRounds`=4).
- Tool-call execution: `Coach/Orchestration/ToolCallExecutor.swift`.
- Strict JSON output: `Coach/Schema/CoachResponseSchema.swift` → `CoachResponse` → `Coach/Schema/CoachResponseView.swift`.
- View model: `Coach/ViewModels/CoachViewModel.swift`.

**Tool system (the brain's hands) — `Coach/Tools/`:**
- Tool factory: `CoachTool.swift` → `AnyCoachTool.make(name:label:description:parameters:strict:argsType:handler:)`. Handler signature: `@MainActor (Args, ToolExecutionContext) async throws -> ToolResult`.
- **`ToolExecutionContext`** (`CoachTool.swift`) exposes exactly: `modelContext: ModelContext`, `flags: CoachFeatureFlags`, `coordinator: RingSyncCoordinator?`, `var pendingActions: [PendingAction]`.
- `ToolResult`: `.object([String:Any])`, `.encoding(Encodable)`, `.error(String)`. Schema helpers in `enum JSONSchema`: `.string/.number/.boolean/.enumString/.array/.object/.empty`.
- Registration: `ToolRegistry.swift` `init` assembles groups behind flags; **built-in tools win name collisions**, then `SubAppRegistry.shared.aiTools(flags:)` merges in non-colliding sub-app tools. `toolSpecs` sorts by name and appends the hosted web-search spec when enabled.
- **Existing tool groups:** `RetrievalTools.all` (read, always on), `ChartTools.all`, `DiagramTools.all`, `AnalysisTools.all` (always on); `MemoryTools.all` + `ActionTools.writeTools` (gated `writeToolsEnabled`); `ActionTools.measurementTools` (gated `liveMeasurementsEnabled`); `SubAppBuilderTools.all` (gated `subAppBuilderEnabled`); `PlatformControlTools.all` (gated `platformControlEnabled`, also force-includes SubAppBuilder); `MediaTools.all` + `ModelDelegationTools.all` (gated `mediaGenerationEnabled`); `WebSearchTool` spec (gated `webSearchEnabled`).
- **Existing write/platform tools:** `set_goal`, `log_user_note`, `log_activity_correction`, `create_activity_session_from_description`, `update_activity_session`, `delete_activity_session`, `trigger_measurement`, `save_memory`, `list_modules`, `set_module_enabled`, `save_subapp`, `uninstall_subapp`, `create_task`, `create_note`, `generate_subapp_spec`, `refine_subapp_spec`, media/delegation tools.

**Data layer:** reads go through deterministic helpers in `Coach/Tools/CoachDataAccess.swift` (date parsing `parseLocalDate`, series, summaries) — tools should NOT raw-query SwiftData ad hoc; add helpers here.

**Confirm flow:** `Coach/Orchestration/PendingAction.swift` (`Kind`: `deleteActivitySession`, `updateActivitySession`, `disableModule`, `uninstallSubApp`; payloads `activityId`, `updates: ActivityUpdates?`, `platform: PlatformActionPayload?`). Executor: `Coach/Orchestration/PendingActionExecutor.swift`. Card UI: `Coach/Schema/CoachActionCardView.swift` (set `isDestructive` for delete/uninstall styling). To add a confirmable write: add a `Kind` case + payload, queue from the tool via `ctx.pendingActions.append(...)` returning `{"needs_confirmation": true}`, handle it in the executor, and style it in the card.

**Flags + settings:** `Coach/Config/CoachFeatureFlags.swift` (computed wrapper) over `Coach/Config/CoachSettings.swift` (stored). Defaults: write/memory/action/liveMeasurement/subAppBuilder OFF; `enablePlatformControl = true`; `enableMediaGeneration = true` (needs muapi key). Settings UI rows: `Coach/Config/CoachSettingsSection.swift` (hosted in `Views/SettingsView.swift` and now also in the in-Coach `CoachSettingsSheet` in `Views/CoachView.swift`).

**System prompt (the brain's self-knowledge):** `Coach/Context/CoachPromptBuilder.swift` (`systemPrompt(personality:goal:)` + `developerMessage(packet:)`). **Today it is scoped entirely to ring/health** and does NOT mention platform-control, sub-app-builder, task/note, or navigation tools — the single biggest reason enabled tools are under-used. Ambient context packet: `Coach/Context/CoachContextBuilder.swift` → `CoachContextPacket`.

**Modules & registry:** `enum AppModule` + `ModuleManager` and `enum AppRoute` + `destinationView(for:)` in `App/AppTheme.swift`. Sub-app platform: `Platform/SubApp.swift` (`SubApp` protocol; `aiTools(flags:)` defaults to `[]`), `Platform/SubAppRegistry.swift` (`subApps`, `isEnabled`, `setEnabled`, `loadUserSpecs`, `aiTools`, `SubAppRouter.shared`). Navigation deep-links via `AppRoute` and `.switchTab` notification.

**Notes:** model in `Models/LifeOSModels.swift` — `Note` (`id`, `title`, `collectionId?`, `aiSummary?`, `createdAt`, `updatedAt`, cascade `blocks: [NoteBlock]`); `NoteBlock` (`noteId`, `order`, `kind`, `content`, `isChecked`); `NoteBlockKind` (heading, paragraph, todo, quote, aiInsight, bulletList, numberedList, divider, callout); `Collection` (folders — **defined but unused by UI**); `TaskItem`. Views: `Views/NoteEditorView.swift` (`NotesListView` + `NoteEditorView` + `VoiceNoteRecorderView`), `Views/VoiceCaptureView.swift`. Capture pipeline: `Services/VoiceCaptureRouter.swift` → `CapturePlan {title, sections[{heading,bullets}], tasks[{title,group,dayOffset}], transcript}` with AI + deterministic local fallback. Legacy AI helpers: `Services/AIService.swift` (`summarizeNote`, `generateNoteTags`, `complete`, `stream`, `smartSearch`).

**Known gaps (the work):** most modules have **no Coach tools at all** — Protocol (`Medication`/`MedicationLog`/`Routine`), Tasks (create-only, no read/complete/update/delete), Notes (create-only), Day Plan, Mood, Nutrition (`MealLog`), Habits, Symptoms/Labs, Stress, Meditation, Journal, Quit Program (`Vice`/`ViceLog`), Friends. No navigation tool, no profile-write tool, no generic spec-sub-app entity CRUD. Notes search is title-only; tags/collections vestigial; note↔task link lossy; AI is one-shot/menu-buried.

---

## 2. Architecture Target (what we are building toward)

### 2.1 Symmetric, per-module CRUD tools
Each module exposes a small, consistent tool set following one naming convention: `list_<entity>`, `get_<entity>`, `create_<entity>`, `update_<entity>`, `complete_<entity>`/`toggle_<entity>` (where it applies), `delete_<entity>`. Read tools are always-on (cheap, safe). Create/update/toggle apply immediately. **Delete and bulk operations route through `PendingAction`.** All reads go through deterministic helpers added to `CoachDataAccess.swift` (or a per-domain access file alongside it), never ad-hoc queries inside the handler.

Prefer contributing module tools via that module's `SubApp.aiTools(flags:)` conformer (the platform is migrating toward `SubApp`), but the central `ToolRegistry` group pattern is acceptable when a module isn't yet a `SubApp`. Either way, gate the *write* half behind `flags.writeToolsEnabled` (or a dedicated flag) and keep reads ungated.

### 2.2 Platform + navigation tools (the "brain" reach)
- `navigate_to` — open a module/screen via `AppRoute` / `SubAppRouter` / `.switchTab`, returning what was opened. Lets the brain "take me to my sleep trends" or finish an action by showing the result.
- `set_profile` — write name/age/height/weight/units so the model stops self-limiting HR zones and BMI. Immediate, but validated.
- Generic spec-sub-app entity CRUD — read/write rows of an installed `SubAppSpec`'s entities so a brain-built tracker can actually be populated and queried.

### 2.3 Teaching the brain (prompt + context)
- Extend `CoachPromptBuilder.systemPrompt` with a **capabilities map**: a concise description of each tool *class* (health read/analyze/chart, tasks, protocol, notes, day plan, habits, mood, platform control, navigation, media) and **when** to use them, plus the confirm-card rule for destructive writes and the "navigate after acting" pattern. This is what turns inert tools into an actual brain.
- Extend `CoachContextPacket` (via `CoachContextBuilder`) with lightweight ambient state for the most-used modules (e.g. open task counts, today's protocol/day-plan, recent notes) so the model has situational awareness without a tool round-trip.

### 2.4 AI-first Notes
- **Capture-first entry.** The notes `+` opens an AI capture surface (text or voice) that routes through a generalized `CapturePlan` (extend `VoiceCaptureRouter` to accept typed text), producing a drafted, structured note instead of a blank canvas. Manual block editing remains available.
- **Conversational in-note editing.** An inline AI bar in `NoteEditorView` that operates on the `blocks` array via `AIService.stream`/`complete`: "make this a checklist", "tighten paragraph 2", "add a section on X". Render AI output through the existing `aiInsight` block kind (give it real rendering).
- **Real organization.** Add `tags: [String]` (additive) to `Note`; wire `Collection`/`collectionId` into the UI; let AI auto-file (pick/create a collection, assign tags). Add note↔task linkage (FK on `TaskItem` back to `Note`/`NoteBlock`) so toggling one reflects in the other.
- **Semantic search.** Replace title-only filter with content+summary search; use `AIService.smartSearch` for natural-language queries over notes.
- **Consolidate voice.** Unify `VoiceNoteRecorderView` and `VoiceCaptureView` around the single `CapturePlan` pipeline (shared `saveEverywhere`/`resultCard`).

---

## 3. Roadmap (ordered; each item is one safe, shippable iteration)

**Phase A — Teach the brain it has hands (highest leverage, low risk)**
- A1. Extend `CoachPromptBuilder.systemPrompt` with the capabilities map for the *already-existing* platform/task/note tools + the confirm-card and navigate-after-acting rules. Build green. (No new tools — just makes current ones get used.)
- A2. Add `navigate_to` tool (open module/route) behind `platformControlEnabled`; register; add prompt guidance. Confirm immediate.
- A3. Add `set_profile` tool (validated name/age/height/weight/units) behind `writeToolsEnabled`; update prompt + `get_profile_context` note.

**Phase B — Tasks become fully controllable**
- B1. Task reads: `list_tasks` (filters: group, status, due range), `get_task`. Always-on. Add `CoachDataAccess` helpers.
- B2. Task writes: `update_task`, `complete_task`/`toggle_task` (immediate), `delete_task` (confirm via new `PendingAction.Kind`). Add prompt guidance + ambient task counts in context packet.

**Phase C — Protocol / medications / routines**
- C1. Reads: `list_medications`, `get_medication_log`, `list_routines`. C2. Writes: `log_medication_taken`, `create/update_medication`, `delete_medication` (confirm). Routine step toggles.

**Phase D — Daily life modules**
- D1. Day Plan (`list/create/update/complete day_plan_action`). D2. Mood + Nutrition (`log_mood`, `log_meal`, reads). D3. Habits (`list_habits`, `log_habit`, `create_habit`). D4. Quit Program (`get_vice_progress`, `log_vice_event`).

**Phase E — Notes become AI-first**
- E1. Generalize `VoiceCaptureRouter` to accept typed text; add AI capture entry to the notes `+` (drafts a structured note). Consolidate the two voice views onto one `CapturePlan` pipeline.
- E2. Note read/edit tools for the brain: `list_notes`, `read_note`, `append_to_note`/`edit_note_block`, `delete_note` (confirm). 
- E3. Inline conversational editing bar in `NoteEditorView` (streamed) + real `aiInsight` rendering.
- E4. Model additions (additive): `Note.tags: [String]`; wire `Collection`/`collectionId` UI + AI auto-file; note↔task linkage FK.
- E5. Semantic/content search in `NotesListView` via `AIService.smartSearch`.

**Phase F — Generic sub-app data + hardening**
- F1. Generic spec-sub-app entity CRUD tools (read/write installed sub-app rows). F2. Accessibility/Dynamic Type/VoiceOver audit on new surfaces; tests for new `CoachDataAccess` helpers, each new `PendingAction.Kind` executor path, and the generalized `CapturePlan` parser.

---

## 4. THE LOOP PROMPT (paste this each session)

```
You are continuing a long-running project: making the PulseLoop AI Coach chatbox
the "ultimate brain" that can read and modify every module/feature in the app, and
making Notes AI-first. Your single source of truth is docs/BRAIN_LOOP_PROMPT.md
(mission §0, code anchors §1, architecture target §2, roadmap §3, guardrails §5)
and the live tracker docs/BRAIN_PROGRESS.md.

Do EXACTLY ONE iteration, then stop. Follow this loop:

1. ORIENT. Read docs/BRAIN_LOOP_PROMPT.md and docs/BRAIN_PROGRESS.md. If
   BRAIN_PROGRESS.md does not exist, create it from the §3 roadmap with every item
   set to "pending", then treat iteration A1 as current.

2. SELECT. Pick the single highest-priority "pending" iteration (top-to-bottom in
   §3). Restate it in one sentence. If it is too big for one safe, shippable step,
   split it: do the first sub-step now and add the remainder as new pending items.

3. PLAN. Write a short todo list for this iteration only. Verify the exact real
   files from §1 by reading them — never invent file paths, tool names, or model
   fields. Confirm the actual ToolExecutionContext fields and PendingAction.Kind
   cases before using them.

4. IMPLEMENT. Make the change, reusing existing patterns:
   - New tool: an `enum XTools { static var all: [AnyCoachTool] }` built via
     AnyCoachTool.make(...), reading via CoachDataAccess helpers (add helpers there,
     do not raw-query in the handler), returning ToolResult.object/.encoding/.error.
   - Register in ToolRegistry.init behind the right flag (reads ungated, writes
     gated). Add a CoachSettings bool + tolerant decode + CoachFeatureFlags accessor
     + a CoachSettingsSection toggle if a new gate is needed.
   - Destructive/bulk writes: add a PendingAction.Kind case + payload, queue via
     ctx.pendingActions.append(...) returning {"needs_confirmation": true}, handle
     in PendingActionExecutor, style in CoachActionCardView. Reversible writes apply
     immediately.
   - TEACH THE MODEL: every new capability MUST get a short usage line in
     CoachPromptBuilder.systemPrompt, or the brain won't use it. Add ambient state to
     CoachContextPacket/CoachContextBuilder when it aids situational awareness.
   - Design system is law: PulseColors/PulseFont/PulseRadius, components from
     AppTheme.swift + Components.swift, .cursor/rules/design-system.mdc. SF Symbols
     only, no emoji in UI, primary buttons black.
   - Notes work routes capture through the CapturePlan pipeline; additive SwiftData
     fields only.

5. VERIFY. Build and resolve errors before finishing:
   xcodebuild -project PulseLoop.xcodeproj -scheme PulseLoop \
     -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
   Run ReadLints on edited files. Add/adjust tests where §3 calls for them. The app
   MUST build at the end of the iteration.

6. RECORD. Update docs/BRAIN_PROGRESS.md: mark this iteration done with a 1–3 line
   summary (what changed + which files + any new tool names/flags), list follow-ups
   you spun off, and clearly name the NEXT pending iteration.

7. STOP. Post a concise summary: what you did, build status, the next iteration. Do
   not start the next iteration. Do not create a git commit unless I ask.

Rules of engagement:
- Keep the build green; never leave a broken state.
- Prefer small, reversible steps; add tools/fields additively so old paths keep
  working.
- Every new tool gets a system-prompt usage line — an unteachable tool is wasted.
- Destructive writes always use the PendingAction confirm card; reversible writes
  apply immediately.
- If a decision has real product trade-offs (data model shape, what counts as
  destructive, tag/collection design), state your default, proceed, and note it in
  the tracker rather than blocking.
- If you find the roadmap is wrong, propose the fix in the tracker and adjust, but
  still complete one concrete shippable step this iteration.
```

---

## 5. Guardrails (referenced by the loop — the hard rules)

- **Build green every iteration.** End state compiles and runs; Xcode build + ReadLints are the gate.
- **Teach every capability.** A tool that isn't described in `CoachPromptBuilder.systemPrompt` does not exist to the brain. Adding a tool without a prompt line is incomplete.
- **Confirm destructive writes.** Delete and bulk/irreversible operations queue a `PendingAction` and only execute after the user taps Confirm; the model returns `response_type:"action_confirmation"` and never claims the change is done. Reversible writes apply immediately.
- **Deterministic data access.** Tool reads go through `CoachDataAccess` helpers (add new ones there); handlers validate inputs and return structured `ToolResult`. No ad-hoc SwiftData queries scattered in handlers, no arbitrary code execution.
- **Design system is law.** `PulseColors`/`PulseFont`/`PulseRadius`/`PulseLayout` + components from `App/AppTheme.swift` + `DesignSystem/Components.swift`; obey `.cursor/rules/design-system.mdc`. SF Symbols only (no emoji in rendered UI). Primary buttons black, accent sparingly, hairline-bordered cards, calm whitespace.
- **Data integrity.** Additive, lightweight SwiftData migrations only; new fields are optional/defaulted with tolerant decoders. Never drop user data. Note↔task and tag/collection additions must not break existing notes.
- **Security.** No API keys/secrets in source; Keychain only. Prefer the Coach orchestrator over the legacy `AIService` for new AI work.
- **AI-first ≠ AI-only.** Notes keep manual block editing as a fallback; AI is the default, not the sole, path.
- **Accessibility & quality.** Maintain Dynamic Type, VoiceOver labels, 44pt tap targets on every new surface; add tests for new data-access helpers, executor paths, and the capture parser.
- **One iteration at a time.** A single shippable step, then stop — keeping the project reviewable.

