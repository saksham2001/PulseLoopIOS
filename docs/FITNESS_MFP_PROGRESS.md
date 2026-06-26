# Fitness & Nutrition (MyFitnessPal-grade, AI-native) — Progress Log

Loop prompt: `docs/FITNESS_MFP_LOOP_PROMPT.md`. Append a dated entry per iteration.
Scope: only the Fitness/Workout and Nutrition/Food modules. Build + full test suite
green every iteration. Design system: `.cursor/rules/design-system.mdc`.

---

## 2026-06-24 — T6 Verify (loop complete) ✅

- **Build**: green on iPhone 17 Pro (sim id 6215B048…).
- **Tests**: full suite **437 tests, 1 skipped, 0 failures** (`** TEST SUCCEEDED **`),
  incl. the new `FitnessNutritionModelTests`, `NutritionDiaryTests`,
  `FitnessNutritionToolsTests`.
- **Simulator**: installed + launched; app runs stably (no launch crash; process
  present in launchctl).
- **Scope**: changes are confined to the fitness/nutrition modules plus the minimal,
  additive wiring seams modules use — 4 new additive `AppRoute` cases + their
  `RootViews` resolution, the `TrackerView` "Food Diary →" entry link, the two
  `SubApp.aiTools(flags:)` conformances, and two teaching lines in
  `CoachPromptBuilder`. No global chrome, navigation, or unrelated module behavior
  changed.

---

## 2026-06-24 — T5 AI coaching surfaces ✅

- **`AICoachCards.swift`** (new): an on-design `AICoachCard` (icon + headline + sub +
  wrapping suggestion chips) that hands a context-aware prompt to the existing
  multi-agent assistant via `CoachNavigation.shared.askAI` — routes through
  `AgentRouter`, renders in the normal chat + trace. No parallel chat UI. Includes a
  tiny `FlexibleChipLayout` so chips wrap cleanly.
- **`NutritionCoachCard`** (on the Food Diary, under the summary): subtitle shows
  "N kcal left · Mg protein to go" from live totals vs the active goal; chips compose
  prompts pre-filled with the day's macros — "What should I eat next?", "Hit my
  protein", "Review my day".
- **`WorkoutCoachCard`** (on the Fitness dashboard, under the calendar): subtitle shows
  the last session; chips embed recent-workout + template context — "Suggest today's
  workout", "Plan my week" (phrased to route to the **Strategist**), "What am I
  neglecting?".
- **Verify**: build green on iPhone 17 Pro. Cards are pure SwiftUI over the tested
  stores; behavior (prefill plumbing) already covered by `TravelPlusTests`.

---

## 2026-06-24 — T4 AI-native tools (multi-agent) ✅

- **`FitnessTools`** (`Coach/Tools/FitnessTools.swift`): reads `list_workout_templates`,
  `list_workouts`; writes (gated by `writeToolsEnabled`) `log_workout` (free-form
  session), `start_workout` (complete a saved template by id → `WorkoutSessionBridge.
  logSession`, stamps performed), `log_weight` (kg or lb + optional body-fat → a
  `BodyMetric`).
- **`NutritionTools`** (`Coach/Tools/NutritionTools.swift`): reads
  `get_nutrition_summary` (consumed vs goal + calories remaining for a day) and
  `lookup_food` (Open Food Facts per-100g macros + barcode); write `set_nutrition_goal`
  (single active goal via `NutritionStore.setActiveGoal`). Complements the existing
  `log_meal` in `DailyLifeTools`.
- **Wiring**: `FitnessSubApp.aiTools(flags:)` + `NutritionSubApp.aiTools(flags:)` expose
  read tools always and write tools behind `writeToolsEnabled`; `ToolRegistry` merges
  them only for installed modules. Coach turns already route through `AgentRouter`
  (multi-agent), so these tools are available to whichever specialist handles the turn.
- **Prompt**: taught the new tools in `CoachPromptBuilder` (workouts + nutrition lines)
  so the model knows when to read first then act.
- **Tests**: `FitnessNutritionToolsTests` (7) — log_workout persists w/ type, start_workout
  from template logs a session + stamps performed, unknown template errors, log_weight
  lb→kg conversion, single-active goal across repeat sets, summary reflects meals+goal,
  write-tool gating.
- **Verify**: build green; full suite **437 tests, 0 failures**.

---

## 2026-06-24 — T3 Goals & progress ✅

- **`BodyProgressView`** (`AppRoute.bodyProgress`, already linked from the Food Diary):
  a real progress hub replacing the stub. Weight summary (Current / Start / Goal with
  a down/up delta-since-start line), a Swift **Charts** weight-trend line+area chart
  (last 60 weigh-ins) with a dashed goal `RuleMark`, an editable nutrition-goal card
  (kcal + P/C/F), and a measurements card (body-fat / waist / chest) when present.
- **`LogWeightSheet`**: log a weigh-in (weight + optional body-fat + date) writing a
  `BodyMetric`, plus an optional goal-weight field (stored in `@AppStorage
  bodyGoalWeightKg`, kg). All input respects the `WeightUnit` preference (kg/lb) and
  converts to kilograms for storage.
- **`NutritionGoalEditor`**: calorie stepper + per-macro steppers (color-coded), live
  "macros total N kcal" reconciliation footer, saved via `NutritionStore.setActiveGoal`
  (single active goal) — the same goal the Food Diary rings read.
- **Verify**: build green on iPhone 17 Pro. (`BodyMetric`/`NutritionGoal` math already
  unit-tested; this track is UI over tested stores.)

---

## 2026-06-24 — T2 Workout logging session flow ✅

- **`WorkoutSessionView`** (`Views/WorkoutSessionView.swift`): perform a workout from
  a `WorkoutTemplate` — a live elapsed timer, per-exercise cards with editable
  reps/weight fields and a check-off per set, an intensity slider + notes, and a
  running stats header (min / sets done / total volume). "Finish workout" calls
  `WorkoutSessionBridge.logSession`, writing a `WorkoutLog` (top working set as the
  representative entry) and stamping `lastPerformed`.
- **`WorkoutSessionRoute`**: id-based resolver so `AppRoute.workoutSession(UUID)` deep
  links resolve a template (graceful empty-state if deleted).
- **`WorkoutHistoryCard`**: recent logged sessions list (icon, duration · sets · kcal,
  date) — surfaced as a new "Recent Sessions" section on the fitness dashboard so
  completed workouts finally have a home.
- **`FitnessDashboardView` / `WorkoutTemplateRow`**: each template row now has a Start
  (play) button that presents the session sheet; row subtitle shows relative
  "Last performed". Editing remains the row tap. Strength radar/progression charts +
  activity calendar already read template sets / `lastPerformed`, so sessions light
  them up automatically.
- **Tests**: covered by existing `WorkoutSessionBridge` tests (make-log completed-only,
  total volume, persisted session + `lastPerformed` stamp). Session UI is thin over the
  tested bridge.
- **Verify**: build green on iPhone 17 Pro; full suite **green, 0 failures**.

---

## 2026-06-24 — T1 Nutrition food diary ✅

- **`FoodDiaryView`** (new route `AppRoute.foodDiary`): day selector (back any day,
  forward capped at today), a calorie ring + protein/carbs/fat `MacroBar`s reading the
  active `NutritionGoal`, and Breakfast/Lunch/Dinner/Snacks sections with per-section
  subtotals, swipe-to-delete rows, and an "Add food" action per section. New
  `CalorieRing` component (turns red when over budget).
- **`FoodSearchView`** (route `AppRoute.foodSearch`): search Open Food Facts + saved
  foods, "describe a meal" (NL → `MealEstimator`), and a **barcode scan** entry. A
  result opens a `ServingPickerSheet` (¼-serving stepper, live macro preview) that
  writes a `MealLog` into the chosen meal type and saves/refreshes the `FoodItem` for
  fast re-logging (recents).
- **`BarcodeScannerView`**: real `AVCaptureSession` scanner (EAN/UPC/Code128/QR…),
  permission-aware, design-system overlay; decoded code → `OpenFoodFactsService.lookup`.
- **`NutritionStore` / `NutritionDiary`** (`Services/NutritionStore.swift`): pure
  diary math (`NutritionTotals`, grouping, remaining/progress), active-goal management
  (single active goal), recents, and `FoodItem` ↔ `MealLog` / OFF mapping (sodium
  g→mg, per-100g serving).
- **Entry point**: TrackerView's NUTRITION header is now a tappable "Food Diary →"
  link (only module surface touched).
- **Stubs**: `WorkoutSessionView` (T2) and `BodyProgressView` (T3) added as
  placeholders so routes resolve; fleshed out in their tracks.
- **Tests**: `NutritionDiaryTests` (7) — totals, grouped/ordered/excludes other days
  + planned, remaining/progress math, FoodItem scaling + OFF mapping (sodium mg),
  single-active-goal, recents ordering.
- **Verify**: build green; full suite **430 tests, 0 failures**.



- **Nutrition models** (`LifeOSModels.swift`): extended `MealLog` with `fiberG`,
  `sugarG`, `sodiumMg`, `mealType` (new `MealType` enum: breakfast/lunch/dinner/
  snacks with SF-Symbol icons + diary order + `forCurrentTime`), `servings`, and
  `servingDescription` — all additive + defaulted for lightweight migration. Added
  `NutritionGoal` (calorie + macro budget, `caloriesFromMacros` helper), `FoodItem`
  (saved/custom/barcode food, per-serving macros), and `Recipe`/`RecipeItem` (totals
  + per-serving macros). Registered the new models on `NutritionSubApp.models`.
- **Fitness bridge** (`WorkoutSession.swift`): `WorkoutSessionBridge` turns a
  performed `WorkoutTemplate` into a `WorkoutLog` session (`makeLog`, `totalVolume`,
  `logSession`) — completed-only by default, top working set as the representative
  entry, stamps `lastPerformed`. Closes the gap between the strength-template domain
  and the session-log domain so completed workouts show in history/charts.
- **Design fix**: removed `WorkoutType.emoji` (design-system violation) → added
  `displayName`; updated `WorkoutBodyHabitsViews` type picker to use `Image(systemName:
  t.icon)` instead of the emoji.
- **Tests**: `FitnessNutritionModelTests` (9) — MealLog extended-field round-trip,
  MealType time buckets + ordering, NutritionGoal persistence + macro math, FoodItem
  round-trip, Recipe totals/per-serving, template→session bridge (completed-only entry,
  total volume, persisted session + lastPerformed stamp).
- **Verify**: build green on iPhone 17 Pro; full suite **423 tests, 0 failures**.

