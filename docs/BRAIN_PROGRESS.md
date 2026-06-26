# BRAIN_PROGRESS — Ultimate Brain Coach + AI-First Notes

Live tracker for `docs/BRAIN_LOOP_PROMPT.md`. One iteration at a time. Status: `pending` / `in progress` / `done`.

---

## Phase A — Teach the brain it has hands
- **A1** `done` — System prompt now describes platform/task/note/navigation capabilities + confirm-card + navigate-after-acting rules.
- **A2** `done` — `navigate_to` tool (open module/route) via `CoachNavigation.requestedRoute/Tab`, consumed in `MainTabView`.
- **A3** `done` — `set_profile` tool (name/age/sex/height/weight, validated ranges).

## Phase B — Tasks
- **B1** `done` — `list_tasks`, `get_task` (reads, always on).
- **B2** `done` — `update_task`, `complete_task`, `delete_task` (confirm via generic `deleteEntity`).

## Phase C — Protocol / medications / routines
- **C1** `done` — `list_medications`, `get_medication_log`, `list_routines`.
- **C2** `done` — `log_medication_taken`, `create_or_update_medication`, `delete_medication` (confirm), `toggle_routine_step`.

## Phase D — Daily life modules
- **D1** `done` — `get_day_plan`, `set_day_plan_action_status`.
- **D2** `done` — `log_mood`/`list_mood_entries`, `log_meal`/`list_meals`.
- **D3** `done` — `list_habits`, `check_in_habit`.
- **D4** `done` — `list_quit_goals`, `log_quit_event` (on `QuitProgramSubApp.aiTools`).

## Phase E — AI-first Notes
- **E1** `done` — Shared `VoiceCaptureRouter.apply(_:in:)`; `capture_and_file` brain tool reuses it for typed brain-dumps; `VoiceCaptureView` refactored onto the same path.
- **E2** `done` — `list_notes`, `read_note`, `append_to_note`, `edit_note_block`, `set_note_tags`, `link_note_to_task`, `delete_note` (confirm).
- **E3** `done` — `aiInsight` block now renders distinctly (sparkle icon + accent card) in `NoteEditorView`; brain can set/edit blocks inline via `edit_note_block`.
- **E4** `done` — `Note.tags: [String]` and `Note.linkedTaskId` added (lightweight migration); `collectionId` already present.
- **E5** `done (content search)` — `list_notes` query matches title AND body text. (Embedding-based semantic search is a future upgrade.)

## Phase F — Generic sub-app data + hardening
- **F1** `done` — Generic spec-sub-app entity CRUD: `list_spec_entities`, `list_spec_records`, `create_spec_record`, `update_spec_record`, `delete_spec_record` (confirm) in `SpecEntityTools.swift`. Lets the brain read/write any built-in or user-built spec sub-app's records via the shared `DynamicSubAppRecord` table.
- **F2** `done` — `BrainToolsTests.swift` covers tasks, notes, protocol, daily-life, navigation, profile, spec records, and read/write gating (8 tests, all green). Full suite green.

---

### Log
- (init) Tracker created from roadmap.
- Phases A–E implemented incrementally with builds at each phase boundary.
- F1 shipped generic spec-record CRUD; F2 added `BrainToolsTests`.
- Fixed a SIGABRT in spec-record persistence: `DynamicSubAppRecord` had a property
  named `entity`, which collides with CoreData's reserved `NSManagedObject.entity`
  and aborted entity-description construction on first SwiftData access. Renamed to
  `entityName`; also switched the JSON blob from `Data` to a `String` column and
  moved id lookups off UUID `#Predicate`s onto in-memory filtering for robustness.
  All BrainToolsTests + the full suite now pass.
