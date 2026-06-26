# PulseLoop → One Consistent Design System — Loop Prompt

> **How to use this file.** Drop it in the repo at `docs/DESIGN_CONSISTENCY_LOOP_PROMPT.md`. Paste the section titled **"THE LOOP PROMPT"** into Claude (Cursor agent) as a single message at the start of each working session. Claude does exactly one iteration (migrate one screen to the canonical design system), keeps the app building, updates the tracker, and stops. Re-run to advance. Everything else here is reference the prompt points at — keep it in the repo.

---

## 0. North-Star Vision (the fixed mission — never changes between iterations)

**Every screen in PulseLoop looks like it was designed by one person on one day — the Home (Today) screen is the canonical reference, and every other screen is brought into exact visual agreement with it.** Not a redesign: a *consistency pass*. Same canvas, same card primitive, same type ramp, same section rhythm, same buttons, same iconography, same spacing — composed from the **shared** design-system primitives, never re-invented per screen.

The look is **calm, editorial, modular, monochrome**: warm off-white canvas, white cards with soft elevation, Newsreader serif for display titles, Hanken Grotesk for everything else, uppercase eyebrow labels, **black** primary actions and black "hero" cards, SF-Symbol line icons in neutral tiles. Color is reserved for data visualization only — never for chrome.

**Non-negotiables across every iteration:**
- The app must **always build and run** at the end of each iteration. Never leave `main` broken.
- **Design system is law, and there is exactly one.** Every view composes from `PulseColors` / `PulseFont` / `PulseRadius` / `PulseLayout` and the components in `App/AppTheme.swift` + `DesignSystem/Components.swift`. Obey `.cursor/rules/design-system.mdc`. If a screen needs a pattern that isn't a shared component yet, **promote it to a shared component first, then use it** — do not fork a one-off.
- **No raw styling.** No `Color(hex:)` literals, no `.font(.system(...))`, no ad-hoc `RoundedRectangle` card backgrounds, no hardcoded paddings outside the spacing scale, in screen code. These live in the design system only.
- **SF Symbols only, no emoji in rendered UI. Primary buttons & hero cards are black, never accent.**
- **No behavior or data changes.** This is a visual-consistency pass. Don't touch SwiftData models, routing, services, or AI logic except where a view trivially reads them. Additive only.

---

## 1. The Canonical Recipe (the Home screen, written down)

This is the single source of visual truth. Extract it verbatim from the existing Home/Today view and `App/AppTheme.swift`; every other screen must match it.

**Canvas & surfaces**
- Screen background: `PulseColors.canvas` (warm off-white) — the same on *every* screen, including Tracker, You, Inbox, Connect, Settings. No screen uses a different base.
- Cards: the **`PulseCard`** primitive (or `.pulseCardSurface()`) — white fill (`PulseColors.background`), `PulseRadius.large` (20) corners, hairline border + the standard 1px soft shadow. One card style, everywhere. No screen draws its own bordered/filled rectangle.
- Inset/secondary panels (e.g. the AI-insight strip, the capture bar): `PulseColors.fillSubtle` fill, same radius, no shadow.
- "Hero" emphasis card (the *Just this one thing* / activity-streak block): solid **black** (`PulseColors.textPrimary` fill), white text, `PulseRadius.xLarge` corners.

**Type ramp** (`PulseFont`)
- Display titles ("Good evening", "Tracker", "Accountability", "Inbox"): `PulseFont.title*` (Newsreader).
- Body / labels / values: `PulseFont.body*` (Hanken Grotesk).
- Section eyebrows ("UP NEXT", "DAILY GOALS", "STREAKS", "AI INSIGHT"): `PulseFont.micro`, **uppercase**, letter-spaced, `PulseColors.textMuted` — use the shared `EyebrowLabel`.
- Numeric values use `.monospacedDigit()`.

**Controls**
- Primary button: black fill, white text — `PrimaryButton`. Secondary: outline/quiet — `SecondaryButton`.
- Segmented control (Schedule/Protocol/Wellness, Category, Timing): one shared component — gray track (`fillSubtle`), white selected pill with soft shadow, `PulseFont.bodySemibold`. Identical everywhere it appears.
- Small pills/chips: `StatusChip` / `PillToggle` / `ToneChip`.
- Icon tile: SF Symbol centered in a `fillSubtle` rounded square (`PulseRadius.medium`), used for list-row leading icons and stat tiles.

**Rhythm**
- Section = `EyebrowLabel` + optional trailing action, then content, with consistent vertical spacing between sections. List rows inside a card are divided by `borderHairline`, not gaps. Generous, airy whitespace — one idea per block.

> Visual north-star: the prototype `PulseLoop App.dc.html` (Home, Tracker ×3, You, Inbox, Assistant, Voice, Connect, Add-to-Protocol) demonstrates the target composition and rhythm for each screen. Match its layout intent using the real Swift primitives above.

---

## 2. Codebase Context (real anchors — do not invent file names)

**Stack:** SwiftUI + SwiftData. Entry `PulseLoop/PulseLoopApp.swift` → `RootAppView` (`Views/RootViews.swift`). Screens live under `PulseLoop/Views/` and feature folders under `PulseLoop/Modules/`.

**Design system (the only place styling is defined):**
- `App/AppTheme.swift` — `PulseColors` (`canvas`, `background`, `fillSubtle`, `fillMuted`, `borderHairline`, `borderStrong`, `textPrimary/Secondary/Muted/Faint`, `accent`, `chipFill`, plus data colors `heartRate/steps/sleep/...`); `PulseFont` (Hanken body + Newsreader title, presets `largeTitle/heading/subheading/bodyDefault/bodySmall/caption/micro`); `PulseRadius` (`small 10`, `medium 14`, `large 20`, `xLarge 24`, `pill`); `PulseLayout.minTapTarget = 44`; primitives `PulseCard`, `.pulseCardSurface()`, `MetricTile`, `MiniSparkline`, `PrimaryButton`, `SecondaryButton`, `PillToggle`, `StatusChip`, `EyebrowLabel`.
- `DesignSystem/Components.swift` — `ToneChip`, `HeroInsightCardView`, `CoachMessageCard`, `MetricCardButton`, `ProgressRingView`, `DetailCard`, `QuickActionButton`, `ActivitySectionCard`.
- `DesignSystem/ChartViews.swift`, `SleepHypnogram.swift`, `WorkoutMapView.swift` — data viz (the **only** place accent/data colors belong).
- `.cursor/rules/design-system.mdc` — written design law; update it whenever you promote a new shared component.

**Likely shared components still missing (promote these in Phase A as screens need them):** a `SegmentedControl`, a black `HeroCard`, an `IconTileRow` (leading SF-Symbol tile + title/subtitle + trailing accessory), a `SectionHeader` (eyebrow + trailing action). Check before creating — reuse if an equivalent exists.

**Build/lint gate:** `xcodebuild -scheme PulseLoop -destination 'generic/platform=iOS Simulator' build`; `ReadLints` on edited files. Tracker: `docs/DESIGN_CONSISTENCY_PROGRESS.md` (create on iteration 1).

---

## 3. Phased Roadmap (ordered backlog the loop walks through)

Work strictly top-to-bottom. Each iteration is one screen (or one shared component), small, shippable, build-green.

**Phase A — Lock the canonical & fill the primitive gaps**
- A1. Create `docs/DESIGN_CONSISTENCY_PROGRESS.md`. Audit the Home/Today screen against §1 and record the exact tokens/components it uses as the locked reference. Note every divergent pattern you see across the app (different backgrounds, bordered-vs-shadow cards, system fonts, accent in chrome, emoji, one-off segmented controls).
- A2. Promote missing shared components into `AppTheme.swift`/`Components.swift`: `SegmentedControl`, `HeroCard` (black), `IconTileRow`, `SectionHeader`. Give each an Xcode Preview. Document them in `.cursor/rules/design-system.mdc`. (No screen changes yet — just make the parts exist.)

**Phase B — Migrate one screen per iteration to the canonical primitives**
For each screen: swap ad-hoc colors→`PulseColors`, fonts→`PulseFont`, cards→`PulseCard`, sections→`SectionHeader`/`EyebrowLabel`, rows→`IconTileRow`, segmented controls→the shared one, primary actions→black `PrimaryButton`/`HeroCard`. Match the Home rhythm. Fix obvious content bugs as you go (e.g. mislabeled supplements, truncated text). Suggested order:
- B1. **Tracker — Schedule** (stat tiles, AI-insight inset, timeline rows).
- B2. **Tracker — Protocol** (search/add buttons, grouped Supplements/Peptides cards, insight strip).
- B3. **Tracker — Wellness** (Sleep, Mood check-in, 7-day trend, Workouts tiles).
- B4. **You / Accountability** (Streaks, Quit program, black activity-streak hero, Daily goals, Mood trend).
- B5. **Inbox** (notification rows on the canonical card/row).
- B6. **Connect** (web-sync hero, grouped wearable/account sections, status pills).
- B7. **Add-to-Protocol sheet** (fields, segmented Category/Timing, black submit).
- B8. **Assistant** (message bubbles, hero answer card, suggestion chips, composer).
- B9. **Voice capture** (keep the dark mode, but mono — no blue; rings/orb/waveform in grayscale; type ramp consistent).
- B10..Bn. Any remaining screens (Sleep detail, Vitals, Activity, Settings, Onboarding, Module picker) — one per iteration.

**Phase C — Consistency sweep & guards**
- C1. Repo-wide grep pass: zero `Color(hex:)` / `.font(.system` / literal card rectangles / emoji in `Views/` & `Modules/`; accent/data colors only inside chart files. Fix stragglers.
- C2. Accessibility: Dynamic Type, VoiceOver labels, 44pt targets on every migrated screen.
- C3. Add/refresh Xcode Previews for each migrated screen; optional snapshot tests for the shared primitives.

---

## 4. THE LOOP PROMPT (paste this each session)

```
You are continuing a long-running project: making every screen in the PulseLoop
iOS app visually consistent with the Home (Today) screen under one shared design
system. Your single source of truth is docs/DESIGN_CONSISTENCY_LOOP_PROMPT.md
(mission §0, canonical recipe §1, code anchors §2, roadmap §3, guardrails §5) and
the live tracker docs/DESIGN_CONSISTENCY_PROGRESS.md.

Do EXACTLY ONE iteration, then stop. Follow this loop:

1. ORIENT. Read docs/DESIGN_CONSISTENCY_LOOP_PROMPT.md and
   docs/DESIGN_CONSISTENCY_PROGRESS.md. If the tracker does not exist, create it
   from the §3 roadmap with every item "pending" and treat A1 as current.

2. SELECT. Pick the single highest-priority "pending" iteration (top-to-bottom in
   §3). Restate it in one sentence. If it is too big for one safe step, do the
   first screen/component now and leave the rest pending.

3. PLAN. Write a short todo list for this iteration only. Open the real screen
   file(s) and read them; list the exact ad-hoc styles you will replace and the
   canonical primitive each maps to (per §1). Never invent file paths.

4. IMPLEMENT. Bring the screen into exact agreement with the Home canonical:
   canvas = PulseColors.canvas; cards = PulseCard; titles = PulseFont.title*;
   labels/eyebrows = EyebrowLabel; rows = IconTileRow; sections = SectionHeader;
   segmented controls = the shared SegmentedControl; primary actions = black
   PrimaryButton / black HeroCard. Remove every Color(hex:), .font(.system),
   one-off card rectangle, emoji, and chrome accent. If a needed pattern isn't a
   shared component yet, PROMOTE it to AppTheme/Components (with a Preview + a note
   in .cursor/rules/design-system.mdc) and use it. Match the prototype
   "PulseLoop App.dc.html" for layout/rhythm intent. Fix obvious content bugs.
   Do NOT change data models, routing, services, or AI logic.

5. VERIFY. Build and resolve all errors before finishing:
   xcodebuild -scheme PulseLoop -destination 'generic/platform=iOS Simulator' build
   Run ReadLints on edited files. The app MUST build at the end of the iteration.

6. RECORD. Update docs/DESIGN_CONSISTENCY_PROGRESS.md: mark this iteration done
   with a 1–3 line summary + files touched, list any shared components you
   promoted, list follow-ups, and name the NEXT pending iteration.

7. STOP. Post a concise summary: what you migrated, build status, next iteration.
   Do not start the next iteration. Do not create a git commit unless I ask.

Rules of engagement:
- Keep main always building; never leave a broken state.
- One screen (or one promoted component) per iteration. Small and reversible.
- Consistency over cleverness: reuse the shared primitive, don't fork a variant.
- Visual-only: no data/model/routing/service/AI behavior changes.
- If a real trade-off appears (a screen needs a genuinely new pattern), promote it
  to a shared component, note it in the tracker, and proceed rather than blocking.
```

---

## 5. Guardrails (the hard rules)

- **Build green every iteration.** End state compiles and runs. The Xcode build + ReadLints is the gate.
- **One design system, defined once.** Only `App/AppTheme.swift` + `DesignSystem/Components.swift` define styling. Screens compose primitives; they never style raw. Obey `.cursor/rules/design-system.mdc` and update it when you promote a component.
- **No raw styling in screens.** No `Color(hex:)`, no `.font(.system(...))`, no hand-rolled card backgrounds, no magic-number padding outside the scale. SF Symbols only — no emoji in rendered UI.
- **Monochrome chrome.** Black for primary actions and hero cards; `PulseColors` neutrals for everything else. Accent and data colors appear **only** in charts/data viz.
- **Home is the reference.** When unsure, open the Home/Today screen and copy its treatment exactly.
- **Visual-only & additive.** No SwiftData migrations, no routing/service/AI changes. If a view reads a field that doesn't exist, stop and flag it — don't add models in this loop.
- **Accessibility preserved.** Dynamic Type, VoiceOver labels, 44pt tap targets on every migrated screen.
- **One iteration at a time.** A single shippable screen, then stop — the project stays reviewable.
