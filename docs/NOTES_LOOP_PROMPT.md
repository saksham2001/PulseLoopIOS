# PulseLoop → Best-in-Class AI-First Notes + Per-Module Versioning — Loop Prompt

> **How to use this file.** Paste the section titled **"THE LOOP PROMPT"** (§4) into Claude (Cursor agent) as a single message at the start of each working session. Claude does exactly one iteration, updates the tracker `docs/NOTES_PROGRESS.md`, and stops. Re-run to advance. Everything else here (Context, Architecture, Roadmap, Guardrails) is the reference the prompt points Claude at — keep it in the repo.

---

## 0. North-Star Vision (the fixed mission — never changes between iterations)

Two pillars, pursued in parallel:

1. **Notes that out-class the best note-takers — AI-first and intuitive.** The Notes module should feel like Notion's structure + Granola's capture + Apple Notes' speed, but with **AI as the primary surface, not a buried menu**. The user should be able to *talk to their note* ("turn this into a checklist", "tighten section 2", "what did I decide last week about the supplier?") and have it just work, while keeping a fast, frictionless manual block editor as the fallback. Capture (typed or voice) is instant and gets auto-structured. Notes organize themselves (titles, summaries, tags, collections, backlinks) so the user rarely files anything by hand. Search understands meaning, not just titles.

2. **Every module has its own version, and users can update modules when a new version ships.** Today only *registry* (community/spec) sub-apps carry a tracked installed-version + "Update available" affordance (`SubAppRegistryStore.updateAvailable(for:)`, `SubAppRegistryView`). Built-in sub-apps (Notes, Tasks, Sleep, …) declare `var version` (default `"1.0.0"`) but nothing **tracks the installed version per module**, **detects when the running build ships a newer version**, or **lets the user tap "Update"** to migrate. The mission is a **uniform versioning + update model across ALL sub-apps** (built-in and spec/registry), with a clear UI to see each installed module's version and update it when a newer one is available.

**Non-negotiables across every iteration:**
- The app must **always build and run** at the end of each iteration. Never leave the working tree broken.
- **Design system is law.** Every screen uses `PulseColors` / `PulseFont` / `PulseRadius` / `PulseLayout` and components from `App/AppTheme.swift` + `DesignSystem/Components.swift`. Follow `.cursor/rules/design-system.mdc`. **SF Symbols only, no emoji in rendered UI. Primary buttons are black, accent used sparingly, hairline-bordered cards, calm whitespace.**
- **AI-first ≠ AI-only.** Notes always keep manual block editing + manual capture as a fallback. AI is the default path, never the sole one.
- **Backward-compatible data.** SwiftData changes are additive/lightweight (new fields are optional or defaulted, decoders are tolerant). **Never drop or corrupt a user's notes.** Module *updates* must migrate data forward, never wipe it.
- **Reuse the existing seams.** Build on `SubApp` / `SubAppRegistry` / `SubAppRegistryStore` / `SemanticVersion`, the Coach Note tools in `NoteTools.swift`, and the `VoiceCaptureRouter` capture pipeline. Do not fork parallel systems.
- **No secrets in source.** AI keys live in Keychain. Prefer the Coach orchestrator / `AIService` Keychain path for new AI work; never hard-code keys.
- **Every new Coach capability is taught.** A new note tool without a usage line in `CoachPromptBuilder.systemPrompt` does not exist to the brain.

---

## 1. Codebase Context (real anchors — verified; do not invent file names)

**Stack:** SwiftUI + SwiftData. Entry `PulseLoop/PulseLoopApp.swift` → `RootAppView` (`Views/RootViews.swift`). The Coach chatbox is `Views/CoachView.swift`.

### Notes — current state (the thing we're leveling up)
- **Model:** `Models/LifeOSModels.swift`
  - `Note` (`@Model`): `id`, `title`, `collectionId: UUID?`, `aiSummary: String?`, `tags: [String] = []`, `linkedTaskId: UUID?`, `createdAt`, `updatedAt`, cascade `blocks: [NoteBlock]`. (`tags`/`linkedTaskId` already exist — additive migrations from the BRAIN loop.)
  - `NoteBlock` (`@Model`): `id`, `noteId`, `order`, `kindRaw`/`kind`, `content`, `isChecked`.
  - `NoteBlockKind` (enum): `heading, paragraph, todo, quote, aiInsight, bulletList, numberedList, divider, callout`.
  - `Collection` (`@Model`, line ~154): **defined; not yet surfaced in the Notes UI** (only `collectionId` on `Note`).
  - `TaskItem` (`@Model`): notes link to tasks via `Note.linkedTaskId`.
- **Views:** `Views/NoteEditorView.swift` contains `NotesListView` (search is **title-only**, sort recent/A–Z, voice `+` and blank `+`), `NoteListRow`, `NoteEditorView` (Notion-style block editor: title, optional `aiSummary` card, `BlockView` per block, slash menu, bottom toolbar with an **AI menu that is one-shot/buried**: Summarize / Continue / Auto-tag / Add AI insight), `BlockView`, `SlashCommandMenu`, and `VoiceNoteRecorderView` (Granola-style capture → `VoiceCaptureRouter` → result card → `saveEverywhere`).
- **Capture pipeline:** `Services/VoiceCaptureRouter.swift` → `CapturePlan { title, sections[{heading,bullets}], tasks[{title,group,dayOffset}], transcript }` with an AI path + deterministic local fallback, and a shared `apply(_:in:)` / `dueDate(forDayOffset:)`. Typed brain-dumps already route here via the `capture_and_file` Coach tool.
- **Legacy AI helpers:** `Services/AIService.swift` — `summarizeNote`, `generateNoteTags`, `complete`, `stream`, `smartSearch`. (Key in Keychain.)
- **Coach Note tools (the brain's hands on notes):** `Coach/Tools/NoteTools.swift` — `readTools`: `list_notes` (title+body search, optional tag filter), `read_note`; `writeTools` (gated `writeToolsEnabled`): `capture_and_file`, `append_to_note`, `edit_note_block`, `set_note_tags`, `link_note_to_task`, `delete_note` (confirm via `PendingAction`). Registered in `Coach/Tools/ToolRegistry.swift`. Taught in `Coach/Context/CoachPromptBuilder.swift` (Notes line ~50).
- **Routes:** `Platform/SubApps/NotesSubApp.swift` — `NotesRoute { list, editor(UUID?) }`; legacy `AppRoute.notesList` / `.noteEditor(UUID)` still resolve.

### Module / sub-app + versioning — current state (the thing we're standardizing)
- **`SubApp` protocol:** `Platform/SubApp.swift` — every module declares `id: SubAppID`, `displayName`, `iconSystemName`, `summary`, **`var version: String` (default `"1.0.0"`)**, `author`, `origin: SubAppOrigin { builtIn | userCreated | installed }`, `models`, `permissions`, `registerRoutes`, `aiTools`, `dashboardCard`. Built-in conformers live in `Platform/SubApps/*.swift` (e.g. `NotesSubApp`, `TasksSubApp`, `SleepSubApp`, …).
- **Registry (presence/install state):** `Platform/SubAppRegistry.swift` (`SubAppRegistry.shared`) — `subApps`, `installedIDs` (UserDefaults `enabledModules`), `install`/`uninstall`, `installedSubApps`, `registerAllRoutes`, `loadUserSpecs`, `aiTools(flags:)`. **No per-module installed-version tracking here.**
- **Spec sub-apps:** `Platform/SubAppSpec.swift` — `SubAppSpec` carries `var version: SemanticVersion`; `SemanticVersion` (Codable/Comparable, parses `"M.m.p"`). `Platform/SpecSubApp.swift` exposes `var version: String { spec.version.description }`. `Platform/SubAppRegistryService.swift` defines `RegistryListing`, `SubAppRegistryStore` (**the only place that tracks installed versions today**): `installedVersions: [String:String]`, `installedVersion(for:)`, `updateAvailable(for listing:) -> Bool` (compares listing spec version > installed), `markInstalled(_:version:)`, `markUninstalled(_:)`.
- **Update UI today (registry-only):** `Views/SubAppRegistryView.swift` shows "Update to v\(spec.version)" when `store.updateAvailable(for: listing)` and re-installs the newer spec. Built-in modules have **no equivalent**.
- **Where modules are managed/shown:** `Views/LibraryView.swift`, `Views/ModulePickerView.swift`, `Views/SidebarView.swift`, `Views/SettingsView.swift`, `Views/SubAppRegistryView.swift`. `App/AppTheme.swift` holds `AppModule`, `ModuleManager`, `AppRoute`, `destinationView(for:)`.

### Known gaps (the work)
- **Notes UX:** AI is one-shot and menu-buried (no conversational inline bar); capture is voice-only from the list (typed quick-capture not surfaced in the UI); `Collection`/`collectionId` unused in UI (no folders/filtering); search is title-only in the UI (the brain's `list_notes` does body search, but `NotesListView` does not); no backlinks/links between notes; `aiSummary` only set on demand; no per-note AI chat/history; no pinning, no rich previews.
- **Versioning:** built-in sub-apps have a `version` string but **no installed-version ledger**, **no "newer version shipped in this build" detection**, **no update action/migration hook**, and **no UI** to view/update a built-in module's version. The concept exists only for registry specs and isn't unified.

---

## 2. Architecture Target (what we are building toward)

### 2.1 AI-first, intuitive Notes
- **Capture-first entry.** The Notes `+` opens a single fast capture surface accepting **typed text or voice**, routed through `VoiceCaptureRouter` (extend it to accept typed input directly), producing a drafted, structured note (title + sections + extracted tasks) instead of a blank canvas. A "blank note" option remains one tap away.
- **Conversational in-note editing (the headline feature).** Replace the buried one-shot AI menu with an always-available **inline AI command bar** docked in `NoteEditorView`. The user types/dictates an instruction ("make this a checklist", "summarize", "expand the second bullet", "what's missing here?") and the AI **streams** edits onto the `blocks` array via `AIService.stream`/`complete`, rendering interim results in the existing `aiInsight` block kind (already styled). Every AI edit is **undoable** (snapshot blocks before applying); destructive rewrites ask first. Keep the slash menu + manual blocks intact.
- **Self-organizing notes.** Auto-title untitled notes, auto-`aiSummary` on save (debounced), and AI auto-file: pick or create a `Collection` and assign `tags` (reuse `generateNoteTags`). Surface `Collection` in the UI: a folder/collection chip row + filter in `NotesListView`, and a collection picker in the editor.
- **Real search.** Make `NotesListView` search match **title + body + tags** (mirror what `list_notes` already does) and add an optional **semantic/natural-language** mode via `AIService.smartSearch` for queries like "the note about the supplier deadline".
- **Links + backlinks.** Allow `[[note title]]`-style references between notes (additive: a `links: [UUID]` or a lightweight link table) and show a "Linked references / backlinks" section. Keep `Note.linkedTaskId` ↔ task in sync (toggling the task reflects on the note and vice-versa).
- **Polish for parity with the best:** pin/favorite notes, richer list previews (icon/collection/tag chips), word count, last-edited, keyboard-first block navigation, and graceful empty/loading states. All design-system styled, all accessible (Dynamic Type, VoiceOver, 44pt targets).
- **Brain symmetry.** Anything the user can do AI-first in the editor, the Coach can do too via `NoteTools` (extend tools as needed — e.g. `summarize_note`, `set_note_collection` — and teach each in the prompt).

### 2.2 Uniform per-module versioning + update
- **Single source of truth for "module version".** Promote the version concept to cover **all** `SubApp`s. Built-in sub-apps expose a real `version` (bump it when their behavior/data changes); spec sub-apps already expose `spec.version`. Normalize on `SemanticVersion` (parse the `SubApp.version` string; treat unparseable as `1.0.0`).
- **Installed-version ledger for every module.** Add an installed-version store keyed by `SubAppID` (mirror `SubAppRegistryStore.installedVersions`, or generalize it) recording the version that was active when the user installed/last-updated each module. Set it on `install`/update; clear on full uninstall.
- **Update detection.** A module has an update available when the **running build's** `SubApp.version` (or the registry listing's spec version) is **greater than** the stored installed version. Expose `availableUpdate(for: SubAppID) -> SemanticVersion?` and an `@Observable`/published list of modules with updates so badges can react.
- **Update action + migration hook.** "Update" applies the new version: run any module-specific **forward migration** (a new optional `SubApp` hook, e.g. `func migrate(from: SemanticVersion, to: SemanticVersion, context:)` with a default no-op) and then record the new installed version. Migrations are **additive and data-preserving**; risky ones surface a confirm. Updating must never delete user data.
- **Update UI.** Show each installed module's **current version** and an **"Update available → vX"** affordance wherever modules are managed (`LibraryView` / `SettingsView` module rows and `ModulePickerView`), plus an aggregate "Updates" entry/badge. Reuse the existing registry pattern in `SubAppRegistryView` so built-in and spec modules look consistent. SF Symbols, black primary "Update" buttons, calm layout.
- **Coach reach (optional, later).** A `list_module_updates` / `update_module` tool so the user can ask the brain "are any of my modules out of date?" and update from chat (update-with-migration is a confirmable `PendingAction`).

### 2.3 Shared principles
- Prefer extending the existing `SubApp` / `SubAppRegistry` / `SubAppRegistryStore` seams over new parallel managers.
- All Notes reads used by Coach go through `NoteTools` + (where shared) `CoachDataAccess` helpers; UI reads use `@Query`/`FetchDescriptor` as today.
- Additive SwiftData only; new fields optional/defaulted; tolerant decoders.

---

## 3. Roadmap (ordered; each item is one safe, shippable iteration)

**Phase A — Versioning foundation (low risk, unblocks the update UX)**
- A1. Give each built-in `SubApp` a real `version` (audit conformers in `Platform/SubApps/*.swift`; keep `"1.0.0"` unless behavior already diverged). Add a `SemanticVersion(forSubApp:)`/parse helper that tolerates bad strings. Build green; no UI yet.
- A2. Generalize the installed-version ledger to all modules: an installed-version store keyed by `SubAppID` (extend `SubAppRegistryStore` or add a sibling), written on `SubAppRegistry.install` and cleared on `uninstall`. Backfill existing installs to their current `version` on first run (no false "update available").
- A3. Add `availableUpdate(for:)` + an observable "modules with updates" list. Add the optional `SubApp.migrate(from:to:context:)` hook (default no-op) and an `update(_:)` path on the registry that runs migration then records the new version.

**Phase B — Update UI**
- B1. Show **current version** on each installed module row in `LibraryView` (and/or `SettingsView` module section) using design-system components.
- B2. Show **"Update available → vX"** with a black "Update" button on rows where `availableUpdate` is non-nil; tapping runs the update path (with confirm if the migration declares itself risky). Mirror `SubAppRegistryView`'s existing registry-update affordance so both look identical.
- B3. Aggregate **"Updates"** badge/entry (count of modules with updates) surfaced where modules are managed; refreshes via the observable list + `.installedModulesChanged`.

**Phase C — Notes: capture-first + inline AI bar (the headline)**
- C1. Extend `VoiceCaptureRouter` to accept typed text; add a **capture-first entry** to the Notes `+` (typed or voice → structured draft), with a one-tap "blank note" fallback. Consolidate on the shared `apply(_:in:)` path.
- C2. Add the **inline AI command bar** to `NoteEditorView` (replaces the buried menu as the primary AI surface; menu actions can remain as quick presets). Streams edits onto `blocks`, renders via `aiInsight`, shows progress.
- C3. **Undo/confirm** for AI edits: snapshot blocks before an AI mutation; offer Undo; ask before large/destructive rewrites.

**Phase D — Notes: organization + search**
- D1. Surface `Collection` in the UI: collection chip row + filter in `NotesListView`, collection picker in `NoteEditorView`; AI auto-file (pick/create collection + tags) on capture/save.
- D2. Make `NotesListView` search match **title + body + tags**; add an optional **semantic** mode via `AIService.smartSearch`.
- D3. Auto-title + debounced auto-`aiSummary` on save; render tags as chips in list + editor.

**Phase E — Notes: links, tasks, polish**
- E1. Note↔note links/backlinks (additive model) + a "Linked references" section in the editor.
- E2. Keep `Note.linkedTaskId` ↔ task status in sync both ways; show the linked task inline.
- E3. Pin/favorite, richer list previews, word count, empty/loading states; full accessibility pass on Notes surfaces.

## 4. THE LOOP PROMPT (paste this each session)

```
You are continuing a long-running project with two goals: (1) make PulseLoop's
Notes module a best-in-class, AI-first, intuitive note-taker, and (2) give every
module its own version with a user-facing update flow. Your single source of truth
is docs/NOTES_LOOP_PROMPT.md (mission §0, code anchors §1, architecture §2,
roadmap §3, guardrails §5) and the live tracker docs/NOTES_PROGRESS.md.

Do EXACTLY ONE iteration, then stop. Follow this loop:

1. ORIENT. Read docs/NOTES_LOOP_PROMPT.md and docs/NOTES_PROGRESS.md. If
   NOTES_PROGRESS.md does not exist, create it from the §3 roadmap with every item
   set to "pending", then treat iteration A1 as current.

2. SELECT. Pick the single highest-priority "pending" iteration (top-to-bottom in
   §3). Restate it in one sentence. If it is too big for one safe, shippable step,
   split it: do the first sub-step now and add the remainder as new pending items.

3. PLAN. Write a short todo list for this iteration only. Verify the exact real
   files/types from §1 by reading them — never invent file paths, model fields,
   tool names, or APIs. Confirm the real SubApp protocol members, SemanticVersion
   API, SubAppRegistry/SubAppRegistryStore methods, NoteTools names, and
   VoiceCaptureRouter shape before using them.

4. IMPLEMENT. Make the change, reusing existing patterns:
   - VERSIONING work: extend SubApp / SubAppRegistry / SubAppRegistryStore /
     SemanticVersion — do NOT create a parallel versioning system. Installed-version
     writes happen on install/update; updates run a data-preserving migration hook
     then record the new version. Mirror the existing registry "Update to vX"
     affordance in SubAppRegistryView for consistency.
   - NOTES work: route capture through VoiceCaptureRouter (extend for typed text);
     make AI the primary in-note surface via a streaming inline bar over the blocks
     array; render AI output through the aiInsight block kind; keep manual block
     editing + slash menu as fallback. Snapshot blocks before AI mutations so edits
     are undoable; confirm large/destructive rewrites.
   - New Coach note/module tools: enum XTools { static var all/readTools/writeTools }
     via AnyCoachTool.make(...); reads ungated, writes gated (writeToolsEnabled);
     destructive/irreversible ops queue a PendingAction confirm card. Register in
     ToolRegistry and TEACH each in CoachPromptBuilder.systemPrompt — an untaught
     tool is wasted.
   - Data: additive SwiftData only (optional/defaulted fields, tolerant decoders).
     NEVER drop or corrupt user notes; module updates migrate forward, never wipe.
   - Design system is law: PulseColors/PulseFont/PulseRadius/PulseLayout, components
     from AppTheme.swift + Components.swift, .cursor/rules/design-system.mdc. SF
     Symbols only, no emoji in UI, primary buttons black, accent sparingly.

5. VERIFY. Build and resolve errors before finishing:
   xcodebuild -project PulseLoop.xcodeproj -scheme PulseLoop \
     -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
   Run ReadLints on edited files. Add/adjust tests where §3 calls for them. The app
   MUST build at the end of the iteration.

6. RECORD. Update docs/NOTES_PROGRESS.md: mark this iteration done with a 1–3 line
   summary (what changed + which files + any new fields/tools/flags), list any
   follow-ups you spun off, and clearly name the NEXT pending iteration.

7. STOP. Post a concise summary: what you did, build status, the next iteration. Do
   not start the next iteration. Do not create a git commit unless I ask.

Rules of engagement:
- Keep the build green; never leave a broken state.
- Prefer small, reversible steps; add fields/tools additively so old paths keep
  working and old notes keep opening.
- AI-first, not AI-only: manual note editing and manual capture always remain.
- Module updates preserve data; destructive/irreversible actions confirm first.
- Every new Coach tool gets a system-prompt usage line.
- If a decision has real product trade-offs (link model shape, what counts as a
  "risky" migration, semantic-search UX, when to auto-summarize), state your
  default, proceed, and note it in the tracker rather than blocking.
- If you find the roadmap is wrong, propose the fix in the tracker and adjust, but
  still complete one concrete shippable step this iteration.
```

---

## 5. Guardrails (referenced by the loop — the hard rules)

- **Build green every iteration.** End state compiles and runs; Xcode build + ReadLints are the gate.
- **Data integrity above all.** Additive, lightweight SwiftData migrations only; new fields optional/defaulted with tolerant decoders. **Never drop or corrupt user notes.** Module *updates* run forward-only, data-preserving migrations — a bad/uncertain migration confirms before running and never wipes records.
- **AI-first, not AI-only.** Notes keep a fast manual block editor, slash menu, and manual capture as fallbacks. AI is the default surface, not the only one.
- **AI edits are reversible.** Snapshot the blocks array before any AI mutation; offer Undo. Large or destructive rewrites ask for confirmation first.
- **One versioning system.** Extend `SubApp` / `SubAppRegistry` / `SubAppRegistryStore` / `SemanticVersion`. Do not fork a second version/update mechanism. Built-in and spec/registry modules must look and behave consistently in the update UI (mirror `SubAppRegistryView`).
- **Teach every Coach capability.** A note/module tool not described in `CoachPromptBuilder.systemPrompt` does not exist to the brain. Destructive/irreversible Coach writes use the `PendingAction` confirm card; reversible writes apply immediately.
- **Deterministic, safe data access.** Coach reads go through `NoteTools` + shared `CoachDataAccess` helpers (add helpers there, no ad-hoc queries scattered in handlers). No arbitrary code execution.
- **Design system is law.** `PulseColors`/`PulseFont`/`PulseRadius`/`PulseLayout` + components from `App/AppTheme.swift` + `DesignSystem/Components.swift`; obey `.cursor/rules/design-system.mdc`. SF Symbols only (no emoji in rendered UI). Primary buttons black, accent sparingly, hairline-bordered cards, calm whitespace.
- **Security.** No API keys/secrets in source; Keychain only. Prefer the Coach orchestrator / Keychain-backed `AIService` for new AI work.
- **Accessibility & quality.** Maintain Dynamic Type, VoiceOver labels, and 44pt tap targets on every new surface; add tests for version-compare/update detection/migration, the typed-capture parser, and note search.
- **One iteration at a time.** A single shippable step, then stop — keeping the project reviewable.

