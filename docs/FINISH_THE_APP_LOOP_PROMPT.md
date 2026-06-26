# PulseLoop → Finish the App — Run-to-Done Loop Prompt

> **How to use.** Put this at `docs/FINISH_THE_APP_LOOP_PROMPT.md`. Paste the **"THE LOOP PROMPT"** block into your agent (Cursor) as one message each session. It does **exactly one iteration**, keeps the app building, updates the tracker, and stops. Re-run to advance. Keep going until every box in the **Definition of Done** (§0) is checked. Reference north-star: the prototype `PulseLoop App.dc.html` (the look, the flat graphs, the theme modes, the wired navigation).

---

## 0. Definition of DONE (the loop runs until ALL of these are true)

The app is "done" when:

1. **Beautiful & consistent.** Every screen uses the one design system — `PulseColors` / `PulseFont` / `PulseCard` / shared components — matching the Home reference. No raw `Color(hex:)`, no `.font(.system)`, no one-off cards, no emoji in UI. Three theme modes (**Light / Dark / Color**) re-skin every screen correctly; Color uses a single reserved accent for data/active states only.
2. **Nothing is a dead end.** Every button, row, tab, chip, and card either performs a real action, navigates to a real screen, or opens a sheet. Zero no-op controls. Every list item drills into a detail screen. Every "Log / Add / Check-in / Connect / Search" control reaches a working flow.
3. **Nothing is missing.** First-run **onboarding** exists. Every feature in the menu opens a real screen (not a shared placeholder). Each module has: a populated state with realistic data **and** a genuine empty state; a detail screen; a way to add/log. **Inbox, Settings, Connect, Assistant, Voice** are complete.
4. **Lived-in, not empty.** Seed realistic sample data everywhere so screens never read as all-zero. Provide a "reset to empty" path so empty states are still reachable/testable.
5. **The single next action is always obvious.** Every primary screen surfaces its one most-important next action in the black hero card pattern.
6. **Data is shown beautifully.** Flat graphs (bars, area-line, rings, hypnogram) for sleep, HRV/readiness, mood, activity, goals — themed by the accent token, with week/month ranges where relevant.
7. **AI is connective tissue.** The assistant FAB carries the current screen's context; the Inbox holds proactive, generated nudges; each module exposes its AI action.
8. **Quality.** Builds green; Dynamic Type + VoiceOver + 44pt targets pass; the spec/runtime/credits paths (if present) keep their tests green.

The loop is NOT done while any control no-ops, any screen is a placeholder, any screen breaks the design system, or onboarding/detail/empty states are missing.

---

## 1. Backlog (ordered — the loop walks top to bottom)

**Phase A — Shared foundation (do first; unblocks everything)**
- A1. Promote the missing shared components used by the prototype: `SegmentedControl`, black `HeroCard` ("just one thing"), `IconTileRow`, `SectionHeader`, `StatBar`/`BarChart`, `AreaLineChart`, `ProgressRing`, `Hypnogram`. Each with an Xcode Preview; documented in `.cursor/rules/design-system.mdc`.
- A2. Token map: a single source mapping the prototype's CSS variables → `PulseColors` (`--bg`→`canvas`, `--surface`→`background`, `--ink`→`textPrimary`, `--inverse`→hero/primary, `--accent`→data/active, etc.) and confirm the three appearance modes (Light/Dark/Color) all resolve. Wire Color mode into `AppAppearance`/`PulseColors`.
- A3. A central nav audit: produce `docs/DEADENDS.md` listing every interactive control and where it currently leads. This becomes the punch-list for Phase C.

**Phase B — Completeness per screen (one screen per iteration)**
Migrate to the shared components AND make it whole: hero next-action, populated + empty states, drill-in detail, add/log flow, real graphs. Order: Home → Tracker (Schedule / Protocol / Wellness) → You/Accountability → Inbox → Connect → Assistant → Voice → each Module screen (Protocol, Sleep, Workouts, Nutrition, Mood, Tasks, Day Plan, Notes, AI Capture, Quit, Travel, Accountability) → Settings.

**Phase C — Kill every dead end (one cluster per iteration)**
Walk `docs/DEADENDS.md`. For each no-op control, give it a real destination: rows → detail; Log/Add/Check-in → the add/log sheet or capture; Search → search results; Connect/Sync → connector flow; chips/quick-actions → the action they name. Re-audit until the file is empty.

**Phase D — Missing flows**
- D1. Onboarding (welcome → choose apps → connect data → pick theme → enter).
- D2. A reusable **Detail** screen (title, hero stat + flat graph, history list, log/edit actions) used by every list item.
- D3. Global search / command palette across modules.
- D4. Notifications / Live Activity / widget surfaces represented and reachable.

**Phase E — AI connective tissue**
- E1. Context-passing FAB (assistant opens with the current module/screen in context).
- E2. Generated Inbox nudges + per-module AI action wired to the Coach orchestrator (structured output, tools, Keychain).

**Phase F — Polish & quality**
- F1. Motion: press states, screen transitions, chart draw-in (respect Reduce-motion).
- F2. Empty/loading/error states for every data surface.
- F3. Accessibility + tests; final design-system sweep (grep for raw color/font/card literals → zero).

---

## 2. Code anchors (real — do not invent paths)

Design system: `App/AppTheme.swift` (`PulseColors`, `PulseFont`, `PulseRadius`, `PulseLayout`, `PulseCard`, `MetricTile`, `MiniSparkline`, `PrimaryButton`, `SecondaryButton`, `PillToggle`, `StatusChip`, `EyebrowLabel`), `DesignSystem/Components.swift`, `DesignSystem/ChartViews.swift` + `SleepHypnogram.swift` (graphs), `.cursor/rules/design-system.mdc`. App entry `PulseLoop/PulseLoopApp.swift` → `Views/RootViews.swift`; screens under `Views/` and `Modules/`; features enumerated in `AppModule` (`App/AppTheme.swift`). Build: `xcodebuild -scheme PulseLoop -destination 'generic/platform=iOS Simulator' build`. Trackers: `docs/FINISH_PROGRESS.md` (create iteration 1) + `docs/DEADENDS.md`.

---

## 3. THE LOOP PROMPT (paste each session)

```
You are continuing a long-running project: finishing the PulseLoop iOS app until
it meets the Definition of Done in docs/FINISH_THE_APP_LOOP_PROMPT.md §0 — beautiful,
every control leads somewhere real, and nothing is missing. Sources of truth: that
file (§0 done-criteria, §1 backlog, §2 anchors) + docs/FINISH_PROGRESS.md +
docs/DEADENDS.md. Visual north-star: the prototype PulseLoop App.dc.html.

Do EXACTLY ONE iteration, then stop:

1. ORIENT. Read the loop file, FINISH_PROGRESS.md, DEADENDS.md. Create the trackers
   if missing (DEADENDS.md = full audit of every interactive control + where it
   leads; mark no-ops).
2. SELECT. Pick the single highest-priority unmet item (Phase A→F order; within a
   phase, top-down). Restate it in one sentence. Split if too big for one safe step.
3. PLAN. Short todo list for THIS iteration. Read the real files you'll touch.
4. IMPLEMENT. Build it with the shared design-system components only (promote a
   shared component if one is missing, with a Preview). Kill dead ends: every
   control you touch must lead to a real screen/sheet/action. Seed realistic data
   AND keep a real empty state. Add the hero next-action, drill-in detail, and flat
   graphs where the screen needs them. SF Symbols only; black hero/primary; accent
   only for data/active; no raw color/font/card literals; no emoji.
5. VERIFY. Build green; ReadLints on edited files; add tests where §1 calls for it.
   Update DEADENDS.md (remove the controls you wired; add any new ones).
6. RECORD. Update FINISH_PROGRESS.md: what changed + files, the Definition-of-Done
   boxes now satisfied, follow-ups, and the NEXT item.
7. STOP. Summarize: what you did, build status, remaining dead ends count, next
   item. Don't start the next iteration. No git commit unless asked.

Rules: keep main building; one shippable step; reuse the shared primitive (never
fork a variant); additive SwiftData only (never drop user data); if a real product
trade-off appears, pick a sensible default, note it, proceed. Keep going across
sessions until EVERY Definition-of-Done box in §0 is checked and DEADENDS.md is empty.
```

---

## 4. Guardrails
- Build green every iteration; never leave main broken.
- One design system, defined once; promote shared components instead of forking.
- Zero dead ends — re-audit `DEADENDS.md` until empty.
- Realistic seeded data + a reachable empty state for every data surface.
- SF Symbols only, no emoji; black hero/primary buttons; accent only for data/active.
- Additive SwiftData migrations; Keychain for keys; Coach orchestrator for AI.
- Accessibility (Dynamic Type, VoiceOver, 44pt) and tests are part of "done", not optional.
- One iteration at a time; stop after each so the project stays reviewable.
