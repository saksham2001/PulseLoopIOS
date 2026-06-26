# NOTES_PROGRESS — Best-in-Class AI-First Notes + Per-Module Versioning

Live tracker for `docs/NOTES_LOOP_PROMPT.md`. Status: `pending` / `in progress` / `done`.
One iteration per session; mark done with a 1–3 line summary, then name the next pending item.

---

## Phase A — Versioning foundation
- **A1** `done` — `SubApp` now exposes `semanticVersion` (tolerant parse via new `SemanticVersion.parseOrDefault(_:)` in `SubAppSpec.swift`); `NotesSubApp` declares an explicit `version "1.0.0"` to set the pattern. Built-ins keep `1.0.0` default until behavior diverges. Build green.
- **A2** `done` — `SubAppRegistry` gained a UserDefaults-backed installed-version ledger keyed by `SubAppID` (`installedVersions`, `installedVersion(of:)`, `recordInstalledVersion`): written on `install`, cleared on `uninstall`, with `runVersionBackfill()` (called from `RootViews.task`) stamping existing installs at current version so no spurious updates.
- **A3** `done` — Added `SubApp.migrate(from:to:context:) -> Bool` hook (default no-op/safe) + `SubAppRegistry.availableUpdate(for:)`, `modulesWithUpdates`, and `applyUpdate(_:context:)` (runs data-preserving migration then records new version; migration failure leaves version unchanged). Build green.

## Phase B — Update UI
- **B1** `done` — New `ModuleUpdatesView` ("Modules" manage screen) lists every installed module with icon + "Version x.y.z" + an "Up to date" marker, sorted by name. Reads versions from the registry ledger.
- **B2** `done` — Per-row "Update to vX" black button runs `SubAppRegistry.applyUpdate(_:context:)`; risky updates (`updateNeedsConfirmation`) prompt an alert first. `SubApp.migrate` is now a void data-preserving hook plus a pure `updateNeedsConfirmation(from:to:)` query. Mirrors `SubAppRegistryView`.
- **B3** `done` — Aggregate "N updates available → update all" banner in `ModuleUpdatesView`, plus a `ModuleUpdatesRow` in `SettingsView` Tools with a live count badge; both refresh via `.installedModulesChanged`. New `AppRoute.moduleUpdates` wired in `RootViews`.

## Phase C — Notes: capture-first + inline AI bar
- **C1** `done` — `VoiceCaptureRouter.plan(from:)` already accepts any text, so the capture pipeline is input-agnostic. `VoiceNoteRecorderView` now has a `TextEditor` for typed input + a "Generate" button routing typed text through the same pipeline. Notes `+` is capture-first (opens the recorder) with a "Blank note" toolbar fallback. Notes saves migrated to `saveOrLog`.
- **C2** `done` — Inline streaming "Ask AI" command bar in `NoteEditorView` (the primary AI surface): free-form instruction + quick chips (Summarize / Action items / Rewrite / Continue) stream via `AIService.stream` and render into a fresh `aiInsight` block. The old AI menu is now a secondary "…" affordance.
- **C3** `done` — AI edits are additive by default (new `aiInsight` block) with an inline Undo banner that removes only the AI-inserted block (never user content). A separate, explicitly-confirmed "Replace note with this result" destructive path rebuilds the body from the AI result.

## Phase D — Notes: organization + search
- **D1** `done` — Collections surfaced: filter chip row in `NotesListView` (All + each collection) and a collection picker menu in `NoteEditorView` (with inline tag chips). AI auto-file (`AIService.autoFileNote`) picks/creates a collection + merges tags, wired to an "Auto-file" AI action.
- **D2** `done` — List search matches title + body (blocks) + tags + summary. Optional semantic mode (sparkles toggle) ranks notes by intent via an AI index pass (`runSemanticSearch`), no-op offline.
- **D3** `done` — Debounced (~2.5s idle) auto-enhance on save: derives a title from first heading/paragraph when blank (never overwrites a user title) and refreshes `aiSummary`; tags render as chips.

## Phase E — Notes: links, tasks, polish
- **E1** `done` — Note↔note links/backlinks (additive) + "Linked references" section with NavigationLink jumps + NoteLinkPicker.
- **E2** `done` — Two-way `Note.linkedTaskId` ↔ task status sync; inline linked-task section with toggle/unlink/create.
- **E3** `done` — Pin/favorite (swipe + toolbar, pinned sorted to top), richer list previews, word/char count footer, empty + no-match states, a11y labels.

## Phase F — Brain symmetry + hardening
- **F1** `done` — `NoteTools` extended: `summarize_note`, `list_collections`, `set_note_collection` (find-or-create), `link_notes`; taught in `CoachPromptBuilder`.
- **F2** `done` — `list_module_updates` + `update_module` Coach tools; risky updates route through a `.updateModule` confirmable `PendingAction`; taught in prompt.
- **F3** `done` — Tests added (`ModuleVersioningTests`, `NoteToolsTests`, 14 cases): SemanticVersion compare/parse + `parseOrDefault`, `availableUpdate` detection, apply-update-once + version stamping, backfill, `list_module_updates`/`update_module` tools, `set_note_collection` find-or-create, `link_notes` create/remove/self-link guard, `list_notes` title+body search. Capture parser already covered by `VoiceCaptureRouterTests`.

---

### Log
- (init) Tracker created from the §3 roadmap. Next pending iteration: **A1**.
- (A–E) Versioning foundation, module-update UI, capture-first Notes + inline AI bar, organization/retrieval, links/tasks/polish all landed and build-verified.
- (F) Brain symmetry: extended `NoteTools` (summarize/collections/link), added `list_module_updates`/`update_module` Coach tools with a confirmable `.updateModule` PendingAction, and added 14 passing tests. **Roadmap complete.**
