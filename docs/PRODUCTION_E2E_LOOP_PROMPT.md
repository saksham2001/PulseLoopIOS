# Open Loop — Production-Ready, End-to-End PulseLoop (UI/UX)

You are a **senior UI/UX engineer** owning PulseLoop (SwiftUI + SwiftData, iOS).
Run this as an **open loop**: pick the next failing/most-impactful item, fix it
end-to-end (front end **and** backend/data), verify objectively, update the
progress tracker, and repeat **until every Definition-of-Done item passes**. Do
not stop after one iteration. Do not ask for permission between iterations.

> Companion tracker: `docs/PRODUCTION_E2E_PROGRESS.md` (create on first
> iteration; update every iteration). Keep this prompt file unchanged.

---

## Goal (what "done" means)

A fully working, intuitive app that runs correctly end-to-end with **no test /
demo data** in the default experience:

1. **Onboarding collects the user's name** (and the minimum profile needed to
   personalize the app), then drops the user into a real, empty-but-usable app.
2. **No seeded/sample data** appears in normal runs. Every screen has a real,
   well-designed **empty state** that guides the user to add real data.
3. **All Settings and all modules are organized**, discoverable, and consistent
   with the design system.
4. **Image input in the Coach chat works**: the user can attach a photo (library
   or camera) in the chat composer, and the AI receives it as multimodal input
   and responds usefully (meal photo → nutrition; label/barcode → identify & add
   to tracker; screenshot/labs → extract & interpret; general image Q&A).
5. **All bugs fixed** (front end and backend) and **all features work**.

---

## Hard constraints

- **Keep it building & runnable every iteration.** Never leave `main` red.
- **No regressions.** Don't break existing passing tests or working flows.
- **No new test data in the default path.** Demo seeding may remain ONLY behind
  the existing `-seedDemo` launch arg / `seedDemo` debug affordance — never in a
  clean install.
- **Reuse the design system** (`PulseColors`, `PulseFont`, existing components
  in `DesignSystem/` and shared rows/buttons). No ad-hoc colors/fonts.
- **Respect actor isolation.** The app builds with
  `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`; `@MainActor` UI/service code
  must not call into nonisolated contexts incorrectly (and vice-versa).
- **Secrets stay in Keychain.** Never embed keys; never log them.
- **Privacy:** camera/photo usage strings must exist in `Info.plist`; request
  permission at point of use with graceful denial handling.

---

## Ground truth (current state — verify before changing)

Navigation / entry:
- Entry: `PulseLoop/PulseLoopApp.swift` → `RootAppView` (`PulseLoop/Views/RootViews.swift`).
- Onboarding gate: `RootAppView` shows `OnboardingFlowView` when
  `UserProfile.onboardingCompleted != true`; then `ModulePickerView(isOnboarding:)`.
- Primary nav: paged `MainTabView` (Home, Tracker, Ask AI [center → `CoachView`],
  Inbox, You/Friends). Drawer: `SidebarView`. Routes: `destinationView(for:)`.

Onboarding (today):
- `OnboardingFlowView` (`RootViews.swift`) is 4 pages (Welcome/Health/Privacy/
  Comfort) and **does NOT collect the name**. `finish()` creates a default
  `UserProfile()` and sets `onboardingCompleted`/`baselineCompleted = true`.
- Name is only collected later in `ProfileView` (`TextField("Name", …)`).
- Coach has its own 3-step onboarding in `CoachView` gated on
  `settings.hasCompletedOnboarding`.

Seed data:
- Live trigger is the `-seedDemo` arg / `seedDemo` UserDefaults flag block in
  `RootAppView.task` + Settings "Reseed/Clear demo data". `SeedData.seedIfNeeded`
  is dead code. Exercise catalog (`seedExerciseCatalogIfNeeded`) is content, not
  demo data — keep it.
- `SeedData.seedDemo` populates ~66 model types (profile "Rey", activity, sleep,
  tasks, notes, meds, meals, friends, etc.). Ensure none of this appears by
  default.

Settings (`PulseLoop/Views/SettingsView.swift`): sections in order — Appearance,
Comfort, Fitness, Profile, Ring, CloudSync, **CoachSettingsSection**,
**AIModelSettingsSection**, **VoiceSettingsSection**, Tools, Data.

Coach chat & image input:
- Composer in `CoachView.swift` is **text + mic only** — no PhotosPicker/camera.
- `CoachViewModel.send(_ text: String, …)` is text-only; persists text
  `CoachMessage`; runs `CoachOrchestrator.runTurn(userText:)`.
- Transport `Coach/OpenAI/OpenRouterResponsesClient.swift` builds string-only
  `content`; `OpenAIRequestBuilder.message(role:content:)` takes `String`.
- **Reference implementation for multimodal**: `Services/AIService.swift`
  (lines ~226–233) and `Views/TrackerView.swift` (~1203–1222) already build
  `image_url` data-URL content parts for MealScan/ProductScan. Vision-capable
  `AIModel` tiers exist in `Services/AIModel.swift`.

Models: `Models/LifeOSModels.swift`, `Models/PulseModels.swift`,
`Models/FitnessModels.swift`, plus Coach/Platform models, all registered in
`Persistence/ModelContainerFactory.swift` (`coreModels`).

Tests: `PulseLoopTests/` (26 files incl. `SmokeFlowTests`, `CoachTests`,
`VoiceEngineCoordinatorTests`, `MealEstimatorTests`, …).

---

## Priority order (core flows first, then sweep)

Work top-down; only move on when the current tier's DoD passes.

**Tier 0 — Clean-slate correctness**
- Confirm a fresh install (no `-seedDemo`) shows onboarding then an empty app.
- Audit every view for hardcoded/sample/preview data leaking into the real UI.

**Tier 1 — Onboarding → identity**
- Add a **Name** step (and any minimal must-have profile fields) to
  `OnboardingFlowView`; persist to `UserProfile.name` in `finish()`.
- Personalize Home/Coach greeting with the captured name.
- Make the Coach's separate onboarding consistent (don't double-ask for things).

**Tier 2 — Home / Today**
- Real empty states + first-actions. No placeholder numbers when there's no data.

**Tier 3 — Coach chat + image input** (headline feature)
- Add an attach affordance (PhotosPicker + camera) to `CoachView.composer`.
- Thread an optional image through `CoachViewModel.send` →
  `CoachOrchestrator.runTurn` → transport as a multimodal `image_url` content
  part (extend `OpenRouterResponsesClient.ingestInput` + `OpenAIRequestBuilder`).
- Ensure the active model is a vision tier when an image is present.
- Render the attached image in the user's chat bubble.
- Make the AI act on it (meal → nutrition log, label/barcode → tracker add,
  labs/screenshot → extract, general → describe/answer). Wire to existing tools
  where possible (MealScan/ProductScan/tracker tools) rather than duplicating.

**Tier 4 — Settings & modules organization**
- Group Settings logically; consistent rows; every toggle/picker actually works.
- Ensure each installable module's screens are reachable, labeled, and bug-free;
  module install/uninstall reflects in nav (tabs/sidebar) correctly.

**Tier 5 — Full sweep**
- Walk every route in `destinationView(for:)` and every module; fix bugs, dead
  buttons, broken navigation, layout issues, and backend/data errors.

---

## Iteration procedure (repeat)

1. **Pick** the highest-priority unmet item (respect tier order).
2. **Reproduce / inspect**: read the relevant files; if it's a runtime bug, run
   on simulator and capture the actual behavior/log before fixing.
3. **Fix** front end + backend together so the feature works end-to-end.
4. **Verify objectively** (see checks below). Add/adjust a test when feasible.
5. **Update** `docs/PRODUCTION_E2E_PROGRESS.md`: what changed, files touched,
   check results, what's next.
6. **Commit-worthy stopping point?** Only if the user asked to commit. Otherwise
   continue to the next item.

---

## Objective verification each iteration

- **Build green:**
  `xcodebuild build -project PulseLoop.xcodeproj -scheme PulseLoop -destination 'platform=iOS Simulator,id=9B6A3F66-11A9-46B4-800C-0E317A845960'`
- **Tests pass (no regressions):**
  `xcodebuild test -project PulseLoop.xcodeproj -scheme PulseLoop -destination 'platform=iOS Simulator,id=9B6A3F66-11A9-46B4-800C-0E317A845960'`
  (run at least the touched suites + `SmokeFlowTests`).
- **Clean-install check:** erase app data / fresh install, launch **without**
  `-seedDemo`, confirm onboarding appears and no demo data is present.
- **Run on simulator** and exercise the changed flow:
  install + `xcrun simctl launch` the booted iPhone 17.
- **No new linter errors** in touched files.

### Per-feature objective checks
- **Onboarding name:** after completing onboarding with name "Test User",
  `UserProfile.name == "Test User"` and it shows in Home/Profile greeting.
- **No test data:** on a clean install, counts of demo-only entities
  (`MealLog`, `TaskItem`, `Friend`, `SleepSession`, etc.) are **0** until the
  user adds them.
- **Coach image input:** attaching a meal photo produces a reply that references
  the image content (not a generic "I can't see images" response); the request
  body contains an `image_url`/multimodal content part; the image renders in the
  chat transcript.
- **Modules:** installing/uninstalling a module updates nav without a crash;
  every visible route opens without error.

---

## Definition of Done (all must hold)

- [ ] Fresh install → onboarding asks for the user's **name**; app starts empty.
- [ ] **Zero** demo/sample data in the default experience; every screen has a
      designed empty state.
- [ ] Settings are organized; all modules reachable, labeled, and functional.
- [ ] Coach chat supports **image attachment** (library + camera) and the AI
      acts on the image correctly across the four behaviors.
- [ ] All known front-end and backend bugs fixed; every feature works
      end-to-end.
- [ ] Build green, tests pass (incl. smoke), no new linter errors, verified on
      the iPhone 17 simulator.
- [ ] `docs/PRODUCTION_E2E_PROGRESS.md` reflects the final state.

---

## Notes / gotchas

- Don't delete the exercise catalog seeding — it's content, not demo data.
- Keep demo seeding available behind the debug flag for development; just never
  in the default path.
- Prefer extending existing tools/services (MealScan, ProductScan, tracker,
  Coach tools) over building parallel image pipelines.
- Watch `@MainActor` isolation when adding image plumbing through services.
- If a "bug" is actually a missing feature with trade-offs, note it in the
  tracker and pick the most intuitive default rather than blocking.
