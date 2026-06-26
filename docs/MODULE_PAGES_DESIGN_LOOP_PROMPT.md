# PulseLoop → Design Every Page in Every Module — Loop Prompt

> **How to use this file.** Keep it in the repo at `docs/MODULE_PAGES_DESIGN_LOOP_PROMPT.md`. Paste the section titled **"THE LOOP PROMPT"** (§4) into Claude (Cursor agent) as a single message at the start of each working session. Claude does **exactly one iteration** — designs the full UI/UX of one module's pages (or one page of a large module), keeps the app building, updates the tracker `docs/MODULE_PAGES_PROGRESS.md`, and stops. Re-run to advance through every module. Everything else here is the reference the prompt points at — keep it in the repo. Visual north-star: the prototype `PulseLoop App.dc.html`.

---

## 0. North-Star Vision (the fixed mission — never changes between iterations)

**Every page of every module/sub-app is fully designed — composed, populated, and finished to the same standard as the prototype `PulseLoop App.dc.html`.** Walk the app module by module; for each module, design *all of its pages* — the root screen, every detail/drill-in, every add/log/edit sheet, plus its empty, loading, and error states — so the module reads as a complete, intentional product, not a stub.

This is a **UI/UX design pass**, not a feature build: lay out each page, establish its hierarchy and rhythm, choose the right primitives, seed realistic content so it looks lived-in, surface the one most-important next action, and visualize data beautifully. Behavior/data plumbing already largely exists — compose the *pages* on top of it; only add view-model glue a screen trivially needs.

The look is **calm, editorial, modular, monochrome**: warm off-white canvas, white cards with soft elevation, Newsreader serif for display titles, Hanken Grotesk for everything else, uppercase eyebrow labels, **black** primary actions and black "hero" cards, SF-Symbol line icons in neutral tiles. Color is reserved for data visualization only — never for chrome.

**A module's pages are "designed" when:**
1. **Every page exists and is composed** — root, detail/drill-in, add/log/edit sheet(s), settings/overflow. No screen is a placeholder, a bare `List`, or a "coming soon".
2. **One design system, matched to Home.** Every page composes `PulseColors` / `PulseFont` / `PulseCard` / `EyebrowLabel` and the shared components. No raw `Color(hex:)`, no `.font(.system)`, no one-off card rectangles, no emoji in UI.
3. **Clear hierarchy & rhythm.** Display title → eyebrow'd sections → cards/rows → one black hero next-action. Generous whitespace, one idea per block, consistent section spacing — matching the Home reference.
4. **Lived-in + every state.** Realistic seeded content so it never reads all-zero, AND a genuine empty state, loading state, and error state for every data surface.
5. **Data shown beautifully.** Flat graphs (bars, area-line, rings, hypnogram, sparkline) from the shared chart components, themed by the accent token, with range toggles where relevant.
6. **Nothing dead.** Every button/row/chip/tab on the page leads somewhere real — a detail, a sheet, or an action. Zero no-op controls. Rows drill in; "Log/Add/Check-in/Connect/Search" reach a real flow.
7. **The module's AI action is present.** Each page surfaces its one relevant AI affordance (insight strip, nudge, or "ask the coach about this") wired to the existing coach, in context.

**Non-negotiables across every iteration:**
- The app must **always build and run** at the end of each iteration. Never leave the working tree broken.
- **Design system is law, and there is exactly one.** Every page composes from `PulseColors` / `PulseFont` / `PulseRadius` / `PulseLayout` + components in `App/AppTheme.swift` and `DesignSystem/Components.swift`. Obey `.cursor/rules/design-system.mdc`. If a page needs a pattern that isn't a shared component yet, **promote it to a shared component first, then use it** — never fork a one-off.
- **SF Symbols only, no emoji in rendered UI. Primary buttons & hero cards are black, never accent. Accent/data colors live only in charts.**
- **Design-only & additive.** This is composition + visual finish. Don't change SwiftData models, routing semantics, services, or AI logic except trivial view glue a page reads. Never drop user data.
- **Match the prototype's intent.** `PulseLoop App.dc.html` is the reference for composition and rhythm; reproduce that intent with the real Swift primitives.

---

## 1. Codebase Context (real anchors — verified; do not invent file names)

**Stack:** SwiftUI + SwiftData. Entry `PulseLoop/PulseLoopApp.swift` → `RootAppView` (`Views/RootViews.swift`) → `MainTabView`. Screens live under `PulseLoop/Views/`; module logic under `PulseLoop/Platform/SubApps/`.

**Design system (the only place styling is defined):**
- `App/AppTheme.swift` — `enum PulseColors` (`canvas`, `background`, `fillSubtle`, `fillMuted`, `borderHairline`, `borderStrong`, `textPrimary/Secondary/Muted/Faint`, `accent`, `chipFill`, plus data colors `heartRate/steps/sleep/...`); `enum PulseFont` (Hanken body + Newsreader title presets — `largeTitle/heading/subheading/bodyDefault/bodySmall/caption/micro`); `enum PulseRadius` (`small 10`, `medium 14`, `large 20`, `xLarge 24`, `pill`); `enum PulseLayout` (`minTapTarget = 44`); `struct PulseCard` + `.pulseCardSurface()`, plus `MetricTile`, `MiniSparkline`, `PrimaryButton`, `SecondaryButton`, `PillToggle`, `StatusChip`, `EyebrowLabel`.
- `DesignSystem/Components.swift` — `ToneChip`, `HeroInsightCardView`, `CoachMessageCard`, `MetricCardButton`, `ProgressRingView`, `DetailCard`, `QuickActionButton`, `ActivitySectionCard`.
- `DesignSystem/ChartViews.swift`, `SleepHypnogram.swift`, `WorkoutMapView.swift` — the data-viz primitives (the **only** place accent/data colors belong). `DesignSystem/ErrorToast.swift` — error surface.
- `.cursor/rules/design-system.mdc` — written design law; update it whenever you promote a new shared component.

**The modules (sub-apps).** Legacy enum `AppModule` in `App/AppTheme.swift` (`name`/`icon`/`description`); each backed by a sub-app in `Platform/SubApps/`. The modules and their current cases:
`Protocol`, `Tasks`, `AI Capture`, `Notes`, `Quit Program`, `Accountability`, `Day Plan`, `Mood`, `Nutrition`, `Sleep`, `Workouts`, `Travel` — plus registered sub-apps `Activity`, `Fitness`, `Friends`, `Health`, `Inbox`, `Journal`, `Meditation`, `Stress`, `Symptoms & Labs`, and spec/registry/user-created sub-apps via `Platform/SpecSubApp.swift` + `SubAppRegistry.swift`.

**Each sub-app's page surface** (`Platform/SubApp.swift`): a sub-app contributes `registerRoutes(with:)` (its pushable screens), `dashboardCard(context:)` (Home card), and `aiTools(flags:)`. Read the sub-app file to learn exactly which screens it owns before designing them.

**Module → primary screen files (real — confirm by reading; a module may own several):**
- **Protocol** → `Views/TrackerView.swift` (Protocol tab), `ProtocolDetailView.swift`, `ProductSearchView.swift`, `ProductScanView.swift`; add-to-protocol sheet in `RecordViews.swift`.
- **Tasks** → `Views/TasksView.swift`.
- **AI Capture** → `Views/VoiceCaptureView.swift`, `VoiceConversationView.swift`.
- **Notes** → `Views/NoteEditorView.swift`, `KnowledgeBaseView.swift`, `LibraryView.swift`.
- **Quit Program** → `Views/QuitProgramView.swift`.
- **Accountability** → the "You" surface in `Views/TodayView.swift` / `HomeView.swift` (streaks, goals, milestones) + `FriendsView.swift`.
- **Day Plan** → `Views/DayPlanView.swift`, `WeekPlannerView.swift`, `MorningBriefView.swift`.
- **Mood** → `Views/WellnessTrackingViews.swift` (mood check-in + trend).
- **Nutrition** → `Views/FoodDiaryView.swift`, `FoodSearchView.swift`, `MealScanView.swift`, `BarcodeScannerView.swift`, `FitnessDashboardView.swift`.
- **Sleep** → `Views/SleepView.swift` (+ `SleepHypnogram.swift`).
- **Workouts** → `Views/WorkoutSessionView.swift`, `WorkoutBuilderView.swift`, `ExerciseLibraryView.swift`, `WorkoutBodyHabitsViews.swift`, `ActivityView.swift`, `BodyProgressView.swift`.
- **Travel** → `Views/TravelView.swift`, `TravelEditViews.swift`.
- **Health / Vitals** → `Views/HealthView.swift`, `VitalsView.swift`, `InsightsChartsView.swift`.
- **Stress / Meditation** → `Views/StressMeditationFinanceViews.swift`, `BreathingExerciseView.swift`.
- **Symptoms & Labs** → `Views/SymptomLabViews.swift`, `MeasurementModal.swift`.
- **Shell / cross-module (design last, for consistency):** `HomeView.swift` / `TodayView.swift`, `TrackerView.swift`, `InboxView.swift`, `CoachView.swift`, `ConnectAccountsView.swift`, `SettingsView.swift`, `ProfileView.swift`, `ModulePickerView.swift`, `ModuleDetailView.swift`, `SubAppRegistryView.swift`, `MySubAppsView.swift`, `CommandPaletteView.swift`.

**Build/lint gate:** `xcodebuild -project PulseLoop.xcodeproj -scheme PulseLoop -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build`; `ReadLints` on edited files. Tracker: `docs/MODULE_PAGES_PROGRESS.md` (create on iteration 1). Seeding for lived-in content: `Persistence/SeedData.swift`.

---

## 2. What "design all the pages of a module" means (the per-module checklist)

For the module you pick this iteration, produce **a complete page set**. Before designing, open the module's sub-app file + its screen file(s) and write its **page inventory** into the tracker. Then design each page against this checklist:

**a. Root / overview page**
- Display title (Newsreader) + an optional uppercase eyebrow context line.
- A **black hero card** carrying the module's single most-important next action ("Log tonight's sleep", "Add to protocol", "Start workout").
- Eyebrow'd sections (`EyebrowLabel` + optional trailing action), composed from `PulseCard` and `IconTileRow`-style rows.
- The module's primary **data viz** (the right chart from `ChartViews`/`SleepHypnogram`) with a range toggle where relevant.
- A populated state with realistic seeded data **and** a real empty state.

**b. Detail / drill-in page(s)**
- Every row on the root drills into a detail: title, hero stat + flat graph, history list, edit/log actions. Reuse `DetailCard` / a shared Detail scaffold.

**c. Add / log / edit / capture sheet(s)**
- Fields on the canonical card, shared `SegmentedControl` for category/timing/type, a **black** submit button. Validation + a clear dismiss.

**d. States**
- Empty (inviting first action), loading (skeleton/placeholder on the real layout), error (`ErrorToast` / inline). No data surface lacks these.

**e. AI affordance**
- One in-context AI element per module — insight strip on the root, or a "ask the coach about this" entry that opens `CoachView` with context. Use the existing coach; don't build new AI logic.

**f. Consistency sweep for the module**
- Zero `Color(hex:)` / `.font(.system)` / one-off card rectangles / emoji in the module's files; accent/data color only inside charts. Dynamic Type, VoiceOver labels, 44pt targets on every control. Add/refresh an Xcode Preview per page.

> If the module is large (e.g. Workouts, Nutrition, Protocol), do **one page of it per iteration** (root first, then each detail, then each sheet) rather than the whole module — keep each iteration small and build-green. Smaller modules (Mood, Quit Program, Notes) can be a single iteration.

---

## 3. Roadmap (ordered backlog the loop walks through, top-to-bottom)

Each iteration = one module's full page set, OR one page of a large module. Work the modules in this order, then finish with the shell.

**Phase A — Lock the page kit (do first; unblocks every module)**
- A1. Create `docs/MODULE_PAGES_PROGRESS.md`. Audit the Home/Today screen and the prototype; record the canonical page recipe (§2a) and the exact tokens/components it uses as the locked reference.
- A2. Promote the shared page-level components every module needs and that aren't shared yet (check first — reuse if present): `SegmentedControl`, black `HeroCard` (next-action), `IconTileRow` (leading SF-Symbol tile + title/subtitle + trailing accessory), `SectionHeader` (eyebrow + trailing action), a reusable **Detail scaffold** (title, hero stat + graph, history list), and an **EmptyState** view. Each with an Xcode Preview; documented in `.cursor/rules/design-system.mdc`. No screen changes yet — just make the parts exist.

**Phase B — Design each module's pages (one module, or one page of a big module, per iteration)**
B1. **Sleep** · B2. **Workouts** (root → session → builder → library → body progress) · B3. **Nutrition** (diary → food search → meal scan → barcode) · B4. **Protocol** (schedule → detail → product search → add sheet) · B5. **Mood** · B6. **Day Plan** (today → week → morning brief) · B7. **Tasks** · B8. **Notes** (editor → knowledge base → library) · B9. **Quit Program** · B10. **Accountability** (streaks/goals/milestones) · B11. **Travel** · B12. **Activity** · B13. **Health / Vitals** · B14. **Stress / Meditation** (+ breathing) · B15. **Symptoms & Labs** · B16. **Friends** · B17. **Journal** · B18. **Fitness dashboard** · B19. **Spec / registry / user-created sub-app screens** (the generic spec-rendered pages, builder, editor).

**Phase C — Shell & cross-module pages (design last, so modules set the standard)**
- C1. **Home / Today** (the reference — refine to perfection). C2. **Tracker** container. C3. **Inbox**. C4. **Coach / Assistant**. C5. **Connect / accounts**. C6. **Settings / Profile**. C7. **Module picker / detail / registry / my sub-apps**. C8. **Command palette / search**.

**Phase D — Whole-app design sweep & guards**
- D1. Repo-wide grep: zero `Color(hex:)` / `.font(.system` / literal card rectangles / emoji in `Views/` & `Platform/SubApps/`; accent/data colors only in chart files. Fix stragglers.
- D2. Every-state pass: confirm empty/loading/error exist on every data surface across all modules.
- D3. Accessibility + Previews: Dynamic Type, VoiceOver, 44pt targets, and an Xcode Preview on every page.

---

## 4. THE LOOP PROMPT (paste this each session)

```
You are continuing a long-running project: designing the full UI/UX of EVERY page
in EVERY PulseLoop module/sub-app, to the standard of the prototype
PulseLoop App.dc.html and the Home (Today) reference screen. This is a design pass:
compose and finish each page (root, detail, add/log/edit sheet, empty/loading/error
states), make it lived-in with realistic data, surface one black hero next-action,
visualize data with the shared charts, and leave no dead control. Your single source
of truth is docs/MODULE_PAGES_DESIGN_LOOP_PROMPT.md (mission §0, code anchors §1,
per-module checklist §2, roadmap §3, guardrails §5) and the live tracker
docs/MODULE_PAGES_PROGRESS.md.

Do EXACTLY ONE iteration, then stop. Follow this loop:

1. ORIENT. Read docs/MODULE_PAGES_DESIGN_LOOP_PROMPT.md and
   docs/MODULE_PAGES_PROGRESS.md. If the tracker does not exist, create it from the
   §3 roadmap with every item "pending" and treat A1 as current.

2. SELECT. Pick the single highest-priority "pending" iteration (top-to-bottom in
   §3). Restate it in one sentence. A whole small module is one iteration; for a
   large module (Workouts, Nutrition, Protocol, Day Plan, Notes) do ONE page now
   (root first, then each detail, then each sheet) and leave the rest pending.

3. PLAN. Open the module's sub-app file (Platform/SubApps/<Module>SubApp.swift) and
   its real screen file(s) from §1. Write the module's PAGE INVENTORY into the
   tracker (root, details, sheets, states). Then write a short todo list for the
   page(s) you are designing this iteration. Never invent file paths or model fields.

4. DESIGN. Compose the page(s) to the §2 checklist using shared primitives only:
   canvas = PulseColors.canvas; cards = PulseCard; titles = PulseFont.title*;
   eyebrows = EyebrowLabel / SectionHeader; rows = IconTileRow; segmented controls =
   the shared SegmentedControl; primary action = black HeroCard / PrimaryButton;
   data = the right chart from ChartViews / SleepHypnogram (accent token only).
   - Give the page a clear hierarchy + one black hero next-action.
   - Seed realistic content (via Persistence/SeedData.swift) so it looks lived-in,
     AND build a genuine empty state, loading state, and error state.
   - Drill every row into a detail; wire every button/chip to a real sheet/action —
     ZERO no-op controls. Add the module's one in-context AI affordance (insight
     strip or "ask the coach about this" opening CoachView with context) using the
     EXISTING coach — do not build new AI logic.
   - If a needed pattern isn't a shared component, PROMOTE it to AppTheme/Components
     (with a Preview + a note in .cursor/rules/design-system.mdc) and use it.
   - Remove every Color(hex:), .font(.system), one-off card rectangle, emoji, and
     chrome accent in the files you touch. SF Symbols only; black hero/primary.
   - Design-only & additive: don't change data models, routing semantics, services,
     or AI logic beyond trivial view glue. Never drop user data.

5. VERIFY. Build and resolve all errors before finishing:
   xcodebuild -project PulseLoop.xcodeproj -scheme PulseLoop \
     -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
   Run ReadLints on edited files. Add/refresh an Xcode Preview for each page you
   designed (populated AND empty state). The app MUST build at the end.

6. RECORD. Update docs/MODULE_PAGES_PROGRESS.md: mark this iteration done with a 1–3
   line summary + files touched + which pages/states are now designed, the module's
   page inventory with each page's status, any shared components you promoted,
   follow-ups, and the NEXT pending iteration.

7. STOP. Post a concise summary: what you designed, build status, next iteration. Do
   not start the next iteration. Do not create a git commit unless I ask.

Rules of engagement:
- Keep main always building; never leave a broken state.
- One module's pages (or one page of a large module) per iteration. Small, reversible.
- Consistency over cleverness: reuse the shared primitive, never fork a variant.
- Every page: clear hierarchy, one black hero next-action, lived-in data, AND
  empty/loading/error states. No dead controls. Charts from the shared components,
  accent/data color only.
- Design-only & additive: no data/model/routing/service/AI-behavior changes; never
  drop user data.
- If a real product trade-off appears (a page needs a genuinely new pattern, or a
  module's page set is unclear), promote a shared component / pick a sensible default,
  note it in the tracker, and proceed rather than blocking.
```

---

## 5. Guardrails (the hard rules)

- **Build green every iteration.** End state compiles and runs; Xcode build + ReadLints are the gate. Never leave `main` broken.
- **One design system, defined once.** Only `App/AppTheme.swift` + `DesignSystem/Components.swift` define styling. Pages compose primitives; they never style raw. Obey `.cursor/rules/design-system.mdc` and update it when you promote a component.
- **No raw styling in pages.** No `Color(hex:)`, no `.font(.system(...))`, no hand-rolled card backgrounds, no magic-number padding outside the scale. SF Symbols only — no emoji in rendered UI.
- **Monochrome chrome.** Black for primary actions and hero cards; `PulseColors` neutrals for everything else. Accent and data colors appear **only** in charts/data viz.
- **Home is the reference.** When unsure how a page should look, open Home/Today and the prototype `PulseLoop App.dc.html` and match the treatment exactly.
- **Every page is whole.** Root + detail(s) + add/log/edit sheet(s) + empty/loading/error states. A module isn't "designed" while any of its pages is a placeholder or any data surface lacks its states.
- **Lived-in by default.** Seed realistic sample data so pages never read all-zero; keep a reachable empty state for testing.
- **Nothing dead.** Every interactive control on a designed page leads to a real screen, sheet, or action. Rows drill in.
- **Design-only & additive.** No SwiftData migrations, no routing/service/AI-behavior changes; only trivial view glue a page reads. Never drop user data.
- **Accessibility preserved.** Dynamic Type, VoiceOver labels, 44pt tap targets, and an Xcode Preview on every designed page.
- **One iteration at a time.** A single module's pages (or one page of a large module), then stop — the project stays reviewable.
