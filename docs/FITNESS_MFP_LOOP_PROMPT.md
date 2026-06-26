# Open-Loop Prompt — "MyFitnessPal-grade, AI-native Fitness & Nutrition modules"

> Paste this whole file to the agent as the brief. Work it as a continuous loop:
> one track at a time, smallest shippable change, **keep the iOS build + full test
> suite green every iteration**, append a dated entry to
> `docs/FITNESS_MFP_PROGRESS.md`, and run on the simulator at the end. Do **not**
> stop until every track is done and acceptance is met.
>
> You are the founder of MyFitnessPal. The app's **Workout/Fitness** and
> **Nutrition/Food** modules should feel as complete and trustworthy as MyFitnessPal
> — a real food diary, barcode scanning, calorie & macro goals, exercise logging with
> session history, weight/measurement tracking with trends — but **AI-native**: the
> in-app multi-agent assistant can log meals/workouts/weight, set goals, look up
> foods, plan workouts, and coach the user in natural language, with the work shown in
> the live agent trace.

---

## NON-NEGOTIABLE 1: Follow the app design system

Every view, sheet, row, button, chip, card, and empty state you add or touch MUST
follow `.cursor/rules/design-system.mdc`. A feature is NOT done if it violates it:

- **No emoji anywhere in rendered UI** — `Image(systemName:)` SF Symbols only.
  (Note: `WorkoutType` in `LifeOSModels.swift` currently stores emoji — replace with
  SF Symbol names.)
- **Colors via `PulseColors.*`**; primary buttons = `Color.black` fill + white text,
  secondary = outlined `borderStrong`. Accent is rare emphasis only.
- **Typography via `PulseFont.*`**; section labels UPPERCASED + tracked + `.textMuted`.
- **Cards**: 16–20px padding, 14–16px radius `.continuous`, 1pt `borderHairline` (use
  `PulseCard`). Inter-card spacing 14px; page padding 20px.
- **Sheets**: `.presentationDetents`, `.presentationDragIndicator(.visible)`,
  `PulseColors.background`, left-aligned bold 22pt title.

## NON-NEGOTIABLE 2: Only modify the modules

Touch ONLY the Fitness/Workout and Nutrition/Food modules and their direct
supporting code:

- Models: `PulseLoop/Models/FitnessModels.swift`, `LifeOSModels.swift`,
  `ExerciseCatalog.swift`.
- Views: `FitnessDashboardView`, `FitnessDashboardCards`, `WorkoutBuilderView`,
  `ExerciseLibraryView`, `WorkoutBodyHabitsViews`, `MealScanView`, and the
  nutrition portions of `TrackerView` (plus new module views you add).
- SubApps: `Platform/SubApps/FitnessSubApp.swift`, `NutritionSubApp.swift`
  (this is where module routes + AI tools are contributed).
- Services: `MealEstimator`, `OpenFoodFactsService`, `ExerciseCatalog`, plus new
  fitness/nutrition services you add.
- Coach tools that belong to these modules (contributed via the sub-apps'
  `aiTools(flags:)`, which `ToolRegistry` already merges) — e.g.
  `Coach/Tools/DailyLifeTools.swift` and new fitness/nutrition tool files.

Do **not** redesign global chrome (tab bar, root navigation, settings, the
orchestrator, the router itself), other modules (sleep, travel, notes, tasks,
journal), or shared design-system primitives. You MAY add new `AppRoute`/`AppModule`
cases and register module routes/tools, since that's how a module surfaces — but keep
edits scoped to wiring the fitness/nutrition modules in.

---

## REUSE WHAT EXISTS (grounding — don't reinvent)

- **Two fitness data layers exist and are disconnected**: `WorkoutTemplate` (strength
  templates → `TemplateExercise` → `ExerciseSet`) and `WorkoutLog` (session log with
  `ExerciseEntry` structs) + `BodyMetric` (weight/measurements). Bridge them so
  completing a template writes a `WorkoutLog` session.
- **`MealLog`** is macro-only (calories/P/C/F + SF-symbol `emoji` field). It lacks
  meal type, servings/quantity, and fiber/sugar/sodium — add those.
- **`OpenFoodFactsService`** already does `search(query:)` and `lookup(barcode:)`
  (returns fiber/sugar/sodium) but is **not wired into meal logging** — wire it.
- **`MealEstimator`** turns NL/photo into nutrition (AI + deterministic fallback) —
  reuse for "describe a meal."
- **Multi-agent router**: `Coach/Orchestration/AgentRouter.swift` (`AgentRole`:
  generalist/strategist/researcher/vision) is already wired into
  `CoachOrchestrator` via `modelOverride`. New module tools automatically run under
  whichever agent the turn routes to — make planning/coaching prompts route to the
  Strategist, food lookups to the Researcher.
- **Tool seam**: `ToolRegistry.toolSpecs` merges `SubAppRegistry.shared.aiTools(flags:)`.
  `FitnessSubApp`/`NutritionSubApp` currently contribute no tools — add them there.

---

## OPEN LOOP — TRACKS (do in order; one PR-sized change each)

### T0 — Data model foundation
- **Nutrition**: extend `MealLog` with `mealType` (breakfast/lunch/dinner/snack),
  `servings`/`quantity`, and `fiberG`/`sugarG`/`sodiumMg` (carry through the OFF data
  that's currently dropped). Add a `NutritionGoal` model (daily calorie + protein/
  carbs/fat targets, optional fiber/sodium). Add a reusable `FoodItem` (saved/custom
  food: name, brand, serving, per-serving macros, optional barcode) and a `Recipe`
  (named set of `FoodItem` portions → computed macros).
- **Fitness**: add a bridge so a completed `WorkoutTemplate` produces a `WorkoutLog`
  session (persist the performed sets, not just the template). Replace `WorkoutType`'s
  emoji raw values with SF Symbol names + a display label.
- Register any new models on `FitnessSubApp.models` / `NutritionSubApp.models` so the
  SwiftData schema picks them up.
- Tests: model round-trips (new fields persist), template→session bridge produces a
  log with the right volume/sets, goal math.

### T1 — Nutrition: a real food diary (MyFitnessPal core)
- A dedicated **Food Diary** screen (new `AppRoute`/route on `NutritionSubApp`):
  day selector, meal-type sections (Breakfast/Lunch/Dinner/Snacks) each listing
  logged foods with calories/macros and per-section subtotals, plus a **day total**
  vs goal (calorie ring + macro bars). Design-system styled.
- **Add-food flow**: search (OpenFoodFacts + saved `FoodItem`s + custom), **barcode
  scan** wired to `OpenFoodFactsService.lookup(barcode:)`, "describe a meal" (NL →
  `MealEstimator`), and quantity/serving picker. Saving writes a `MealLog` with the
  meal type + full macros.
- "My foods"/recently logged for fast re-logging; quick-add calories.
- Tests: barcode lookup → FoodItem mapping; diary groups + subtotals; day total vs
  goal; logging a food creates a correct `MealLog`.

### T2 — Workout logging & history (MyFitnessPal exercise diary)
- **Start/complete a workout**: from a `WorkoutTemplate` (or ad-hoc), log each set's
  actual reps/weight, then finish → write a `WorkoutLog` session with duration and
  computed volume; set `lastPerformed`.
- **Session history** + per-exercise progression (reuse `StrengthProgressionCard`/
  `TotalVolumeRadarCard`); a workout's sets feed the existing charts.
- Cardio sessions (reuse `LiveWorkoutManager` where present) also produce a
  `WorkoutLog`.
- Tests: complete-template flow persists a session with the logged sets/volume;
  history lists sessions; progression reads back correctly.

### T3 — Goals & progress tracking
- **Nutrition goals**: a goal-setting sheet (calorie + macro targets, optionally
  derived from weight goal/activity) persisted as `NutritionGoal`; the diary's rings/
  bars read from it.
- **Weight & measurements**: a dedicated body-progress screen logging `BodyMetric`
  (weight/body-fat/measurements) with a **trend chart** over time and goal weight.
- Tests: goal persistence + consumed-vs-goal math; body-metric trend series builds
  from logs.

### T4 — AI-native tools via the multi-agent assistant
- Contribute fitness/nutrition **coach tools** through `FitnessSubApp.aiTools(flags:)`
  and `NutritionSubApp.aiTools(flags:)` (merged automatically by `ToolRegistry`):
  - Nutrition: `set_nutrition_goal`, `lookup_food` (OFF + saved), `build_recipe`,
    `nutrition_summary` (today vs goal). (`log_meal`/`list_meals` already exist — keep
    and align to the new fields.)
  - Fitness: `log_workout`, `start_workout` (from a template), `log_weight`,
    `list_workouts`, `suggest_workout`/`plan_workout`.
- Each tool uses the testable seams (no real network/credits in tests). Write tools
  gated by `flags.writeToolsEnabled`; read tools always available when the module is
  installed.
- The assistant already runs under the **multi-agent router** — make tool descriptions
  + prompt hints so a "plan my week of workouts" routes to the **Strategist** and a
  "find a food / what's the macros of X" routes to the **Researcher**, while quick
  logging stays on the **Generalist**. Don't modify the router/orchestrator themselves;
  just make the module tools + their guidance fit cleanly.
- Tests: each new tool's arg parsing + effect over a stubbed context (e.g. `log_weight`
  creates a `BodyMetric`; `set_nutrition_goal` persists; `lookup_food` returns
  normalized macros over a stubbed transport).

### T5 — AI coaching surfaces inside the modules
- Add **on-design AI coaching cards** in the modules (not new global chrome):
  - Nutrition: a "Daily nutrition coach" card on the diary that, on demand, asks the
    assistant for guidance toward the day's remaining macros (e.g. "what should I eat
    to hit my protein?") and renders the structured answer + follow-up chips.
  - Fitness: an "AI workout suggestion" affordance that proposes today's session based
    on recent history/templates (routes to the Strategist).
- These call the existing assistant pipeline (multi-agent) — reuse `CoachResponseView`/
  trace rendering; no parallel chat UI. Show the routed agent in the trace.
- Tests/build: cards build for each state (loading/answer/empty); no emoji; design
  system honored.

### T6 — Verify end-to-end
- Build green + full test suite green each iteration. New logic (models, diary math,
  barcode mapping, template→session bridge, each new tool) is unit-tested.
- Run on the simulator: log a food by barcode + by description, set a calorie/macro
  goal and see the rings update, complete a workout from a template and see it in
  history + progression, log a weight and see the trend, and have the assistant log a
  meal/workout and plan a workout via natural language with the routed agent shown.
- Confirm **only the fitness/nutrition modules changed** — diff stays within the files
  listed under "Only modify the modules."

---

## HARD ACCEPTANCE (the whole loop)

- [ ] iOS builds green; full test suite green every iteration.
- [ ] Nutrition module is a real **food diary**: meal-type groups, servings, full
      macros (incl. fiber/sugar/sodium), day totals vs **calorie & macro goals**,
      **barcode scan**, food search, NL meal logging, saved/custom foods.
- [ ] Fitness module logs **real workout sessions**: complete a template → a
      `WorkoutLog` with the performed sets, session history, and progression charts;
      weight/measurement tracking with a trend chart and goal.
- [ ] The **multi-agent assistant** can log meals/workouts/weight, set goals, look up
      foods, and plan/coach workouts via natural language — tools contributed by the
      sub-apps, planning routes to the Strategist, food lookup to the Researcher,
      quick logging to the Generalist, all shown in the trace.
- [ ] **No emoji in UI**; PulseColors/PulseFont; design-system cards/sheets/buttons.
- [ ] Changes are **scoped to the fitness/nutrition modules** — the rest of the app is
      untouched.
- [ ] App runs on the simulator demonstrating the flows above.

---

## WORKING AGREEMENT

- One track per iteration, smallest shippable change, build + tests green before
  moving on. Append a dated line to `docs/FITNESS_MFP_PROGRESS.md` each time.
- Reuse existing seams (`OpenFoodFactsService`, `MealEstimator`, `WorkoutTemplate`/
  `WorkoutLog`/`BodyMetric`, the sub-app `aiTools` merge, the multi-agent router,
  `CoachResponseView`/trace) instead of inventing parallel ones.
- Keep tests free of real network/credits (stub transports; sandbox).
- Follow `.cursor/rules/design-system.mdc` for every pixel; only touch the modules.
- Do not stop until all tracks are done and acceptance is met.
