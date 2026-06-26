# PulseLoop → Comprehensive, AI-First Food / Medication / Peptide Tracker — Loop Prompt

> **How to use this file.** Paste the section titled **"THE LOOP PROMPT"** (§4) into Claude (Cursor agent) as a single message at the start of each working session. Claude does exactly one iteration, updates the tracker `docs/TRACKER_PROGRESS.md`, and stops. Re-run to advance. Everything else here (Context, Architecture, Roadmap, Guardrails) is the reference the prompt points Claude at — keep it in the repo.

---

## 0. North-Star Vision (the fixed mission — never changes between iterations)

Make the **Tracker module** (food / meals, medications, supplements, vitamins, peptides) **comprehensive, AI-first, and production-ready** — a Perplexity-style "answer engine" for anything you put in your body.

1. **Everything is searchable — and if it isn't in the database, the app finds it.** The user can search any food, drug, supplement, vitamin, or peptide. The system tries local knowledge first (`SupplementKnowledge`, `PeptideKnowledge`, `MedicationKnowledge`), then live sources (`OpenFoodFactsService`, `OpenFDAService`), then an **AI research pass** (Perplexity-style: AI + hosted `web_search`) that synthesizes a complete, structured profile with citations. **No dead ends** — every query returns a usable, structured result.

2. **The AI integrates results into the system and persists them.** When a searched item isn't in the local catalog, the AI's synthesized profile is **saved to the database as a reusable catalog entry** (a new `CustomProductInfo` SwiftData record) so it's instantly available next time — for this user and for fuzzy-match/autocomplete — without re-querying. Adding it to the user's protocol/meal log is one tap from the result.

3. **AI-first and intuitive.** Search, label-scan, and natural-language capture ("two eggs and a coffee", "add BPC-157 250mcg subq before bed") are the primary surfaces; manual entry is always the fallback. Results show benefit, mechanism, dose, timing, interactions/warnings, and citations in a calm, scannable card.

4. **Production-ready: every feature in this module works without bugs.** Schedule, Meals, Protocol (meds/supps/peptides), and the search/scan/AI flows are reliable, handle offline + empty + error states gracefully, never crash, never corrupt data, and are fully accessible.

**Non-negotiables across every iteration:**
- The app must **always build and run** at the end of each iteration. Never leave the working tree broken.
- **Design system is law.** Every screen uses `PulseColors` / `PulseFont` / `PulseRadius` / `PulseLayout` and components from `App/AppTheme.swift` + `DesignSystem/Components.swift`. Follow `.cursor/rules/design-system.mdc`. **SF Symbols only, no emoji in rendered UI. Primary buttons black, accent used sparingly, hairline-bordered cards, calm whitespace.**
- **AI-first ≠ AI-only.** Manual entry (the `addProtocolSheet` / `addMealSheet` forms) always remains a working fallback.
- **Backward-compatible data.** SwiftData changes are additive/lightweight (new models, or new fields that are optional or defaulted; tolerant decoders). **Never drop or corrupt a user's meals, meds, or logs.**
- **Reuse the existing seams.** Build on `ProductSearchService`, `SupplementKnowledge`/`PeptideKnowledge`/`MedicationKnowledge`, `OpenFoodFactsService`, `OpenFDAService`, `AIService`, the Coach `ProtocolTools`, and the `SubApp` / `SubAppRegistry` versioning system. Do not fork parallel systems.
- **No secrets in source.** AI keys live in Keychain via `AIService`. The medical/health domain is sensitive: every AI-synthesized profile is clearly labeled as AI-generated and carries a "verify with a professional" disclaimer; never present invented dosing as authoritative medical advice.
- **Bump the module version.** This work materially changes the Protocol + Nutrition sub-apps, so their `SubApp.version` MUST be bumped (see §2.4) and an entry recorded so the per-module update flow surfaces it.
- **Every new Coach capability is taught.** A new tool without a usage line in `CoachPromptBuilder.systemPrompt` does not exist to the brain.

---

## 1. Codebase Context (real anchors — verified; do not invent file names)

**Stack:** SwiftUI + SwiftData. Entry `PulseLoop/PulseLoopApp.swift` → `RootAppView` (`Views/RootViews.swift`). The Coach chatbox is `Views/CoachView.swift`. The Tracker tab is `MainTab.tracker`.

### Tracker UI — current state (the thing we're leveling up)
- **`Views/TrackerView.swift`** — the whole tracker screen. A `PillToggle` segments it into `TrackerSegment { schedule, meals, protocol_, wellness }`. Key pieces:
  - **Schedule:** `statCardsGrid` (meds taken, peptides, calories), `aiInsightCard` (calls `AIService.shared.analyzeProtocolInteractions`), `timelineSection`.
  - **Meals:** `calorieRingCard`, `mealLogSection`, `hydrationSection`; `addMealSheet` uses `SupplementKnowledge.estimateMeal(_:)` for a quick calorie/protein estimate; `MealScanView` photo flow.
  - **Protocol:** `aiProtocolInsights` (uses `SupplementKnowledge.getAllInteractions` / `getStackSuggestions` + `AIService.ProtocolAnalysis`), `routinesSection`, `medicationsSection` (grouped meds/supps/peptides → `ProtocolDetailView`). The big `addProtocolSheet`:
    - autocomplete `filteredNameSuggestions` from `SupplementKnowledge.database` + `PeptideKnowledge.database`/`.stacks` + a local `commonMedications` array;
    - **AI fallback search** `aiSearchIngredient(_:)` → builds an `AISupplementProfile` (in `Views/TrackerSupportingViews.swift`) when the name isn't in local data; `applyAIResult(_:)` autofills the form;
    - label scan `scanProtocolLabel(_:)` via `AIService.shared.complete` (Gemini vision) → fills name/dose/category/timing;
    - peptide reconstitution calculator `reconstitutionCalc`; `saveNewProtocolItem()` builds a `Medication` and inserts it.
  - `ProductScanView` (header camera button) and `MealScanView` are separate scan sheets.
- **`Views/TrackerSupportingViews.swift`** — `AISupplementProfile` struct, `ProtocolItem`, `GroupedProtocolSection`, supporting rows.
- **`Views/ProtocolDetailView.swift`**, **`Views/ProductScanView.swift`**, **`Views/MealScanView.swift`** — detail + scan surfaces.

### Search + knowledge — current state (the engine we're extending)
- **`Services/ProductSearchService.swift`** — `ProductSearchService.search(query:) -> [ProductSearchResult]` already does the tiered search: local KB (`SupplementKnowledge.find`/`fuzzyMatch`) → parallel `OpenFoodFactsService.search` + `OpenFDAService.searchLabels` → `AIProductInference.infer(from:)` (deterministic, label-text heuristics) as last resort. `ProductSearchResult { info: SupplementInfo, source: ProductSource, confidence: Double }`; `ProductSource { localKnowledgeBase, openFoodFacts, openFDA, custom }`. Also `searchFromOCR(texts:)`. **This is the natural home for the new AI-research pass + persistence.**
- **`Services/SupplementKnowledge.swift`** — `SupplementInfo` (Codable: name, aliases, category, defaultDose, emoji, timing, benefit, mechanism, bestTimeReason, stackNotes, interactionNotes, pros, cons). `SupplementKnowledge.database` (loaded from bundled `supplements.json`, falls back to `inSourceDatabase`), `find`, `fuzzyMatch`, `estimateMeal`, `getAllInteractions`, `getStackSuggestions`.
- **`Services/PeptideKnowledge.swift`** — `PeptideInfo`, `PeptideStack`; `database`, `stacks`, `find`, `fuzzyMatch`, `findStack`.
- **`Services/MedicationKnowledge.swift`** — `MedicationInfo`; `database`, `find`, `fuzzyMatch`.
- **`Services/OpenFoodFactsService.swift`** — `OpenFoodFactsProduct`; `search(query:)`, `toSupplementInfo(_:)`. Networking via `NetworkRetry` + `ResponseCache`.
- **`Services/OpenFDAService.swift`** — `FDADrugResult`; `searchDrugs`, `searchLabels`, `toSupplementInfo(_:)`. Same retry/cache stack.
- **`Coach/Tools/WebSearchTool.swift`** — hosted `web_search` tool spec (server-side; used by the Coach orchestrator). Useful reference for a Perplexity-style AI research pass.
- **`Services/AIService.swift`** — `complete`, `stream`, `ProtocolAnalysis` (+ `analyzeProtocolInteractions`), vision via `complete` with image_url. Key in Keychain.

### Data models — current state
- **`Models/LifeOSModels.swift`**: `Medication` (`@Model`: name, dose, `categoryRaw`/`category`, emoji, timing, instructions, cycleDayTotal/Current, isActive, benefit, mechanism, interactionNotes, bestTimeReason, stackNotes), `MedicationCategory { medication, supplement, vitamin, peptide }`, `MedicationLog` (medicationId, status, loggedAt), `MealLog` (name, description_, emoji, calories, proteinG/carbsG/fatG, isPlanned, loggedAt), `Routine`/`RoutineStep`.
- **There is no SwiftData model for a searched/custom catalog entry yet** — searched items only become `Medication`s when added to the protocol. The mission's "save to database" needs a new additive `CustomProductInfo` `@Model` (the reusable catalog row) registered in `ModelContainerFactory` and owned by a sub-app's `models`.

### Coach tools — current state
- **`Coach/Tools/ProtocolTools.swift`** — `readTools`: `list_medications`, `get_medication_log`, `list_routines`; `writeTools`: `log_medication_taken`, `create_or_update_medication`, `delete_medication` (confirm via `.deleteEntity` PendingAction), `toggle_routine_step`. Registered in `Coach/Tools/ToolRegistry.swift`, taught in `Coach/Context/CoachPromptBuilder.swift`. **No meal-logging or product-search tool yet.**

### Module / versioning — current state
- **Two built-in sub-apps back this domain:** `Platform/SubApps/ProtocolSubApp.swift` (id `AppModule.protocol_`, models `Medication`/`MedicationLog`/`Routine`/`RoutineStep`) and `Platform/SubApps/NutritionSubApp.swift` (id `AppModule.nutrition`, model `MealLog`). Both currently rely on the default `version "1.0.0"`.
- **Versioning system (built last roadmap):** `Platform/SubApp.swift` (`var version`, `semanticVersion`, `migrate(from:to:context:)` default no-op, `updateNeedsConfirmation`), `Platform/SubAppSpec.swift` (`SemanticVersion` + `parseOrDefault`), `Platform/SubAppRegistry.swift` (installed-version ledger, `availableUpdate(for:)`, `modulesWithUpdates`, `applyUpdate(_:context:)`, `runVersionBackfill`), `Views/ModuleUpdatesView.swift` (update UI), Coach `list_module_updates`/`update_module` in `Coach/Tools/PlatformControlTools.swift`. **Use this system to ship the version bump.**

### Known gaps (the work)
- Search is **fragmented**: the rich tiered `ProductSearchService` exists but the protocol add-sheet uses its own `aiSearchIngredient` JSON path and local autocomplete; meals use only `estimateMeal`. No single "search anything" surface.
- **No web/Perplexity-style AI research pass** with citations; the AI fallbacks are single-shot JSON or deterministic label heuristics.
- **Nothing persists** a searched item as a reusable catalog row — every miss re-queries.
- No food database search in the UI (Open Food Facts is wired in the service but not surfaced for meals).
- Coach can't search products or log meals.
- Module versions are still `1.0.0` with no record of this upgrade.

---

## 2. Architecture Target (what we are building toward)

### 2.1 One unified "search anything" engine (Perplexity-style)
- **Single entry point:** extend `ProductSearchService` into the one search engine the whole module uses. Tiered, in order, short-circuiting when confident:
  1. **Local catalogs** — `SupplementKnowledge`, `PeptideKnowledge`, `MedicationKnowledge`, **and the new `CustomProductInfo` store** (`find` + `fuzzyMatch`). Instant.
  2. **Live APIs** — `OpenFoodFactsService` (food/supplements) + `OpenFDAService` (drugs), in parallel, as today.
  3. **AI research pass (new, the Perplexity layer)** — when local + APIs miss or are low-confidence, an `AIService`-backed researcher synthesizes a complete structured profile. Prefer grounding it with the hosted `web_search` tool (see `WebSearchTool`) so it cites real sources; return citations alongside the profile. Output decodes into a typed struct (reuse/extend `SupplementInfo` or a richer `ResearchedProduct`), never free text the UI has to parse twice.
- **Every result is structured + sourced:** name, category, dose, timing, benefit, mechanism, interactions/warnings, pros/cons, and (for AI/web results) citations + a confidence + an `isAIGenerated` flag. `ProductSearchResult` already carries `source` + `confidence`; extend as needed.
- **Unified result model:** results from all tiers normalize to one type so the UI renders them identically with a small source badge ("PulseLoop AI", "Open Food Facts", "FDA", "AI research").

### 2.2 AI integrates + persists searched items
- **New SwiftData model `CustomProductInfo` (`@Model`)** — a reusable catalog row mirroring `SupplementInfo`'s fields plus `category`, `source`, `isAIGenerated`, `citations: [String]`, `createdAt`. Additive; register in `ModelContainerFactory`; own it on a sub-app's `models` (Protocol or a small shared sub-app).
- **Persist-on-discovery:** when the AI research pass (or an API result the user accepts) produces a profile not already in any local catalog, save it as a `CustomProductInfo` so future `find`/`fuzzyMatch`/autocomplete hit it instantly. De-dupe by normalized name + aliases. Make `SupplementKnowledge.find`/`fuzzyMatch` (or a new façade) consult `CustomProductInfo` too, so the persisted entries flow back into autocomplete everywhere.
- **One-tap adopt:** from any search result, "Add to protocol" builds a `Medication` (reusing `saveNewProtocolItem`'s mapping) and "Log meal" builds a `MealLog` — both prefilled from the structured profile.

### 2.3 AI-first, intuitive UX (production-ready)
- **A real search surface** in the Tracker: a search field (Protocol + Meals) that streams tiered results into result cards with source badges, benefit/mechanism/dose/timing, warnings, citations, and adopt actions. Replaces the ad-hoc `aiSearchIngredient` button with the unified engine while keeping autocomplete.
- **Natural-language + scan capture stay first-class:** label scan (`scanProtocolLabel`, `ProductScanView`, `MealScanView`) routes through the same engine; NL meal/med capture ("two eggs and toast", "add 5000 IU vitamin D in the morning") parses to structured logs.
- **Disclaimers + safety:** AI/web profiles render an unobtrusive "AI-generated — verify with a professional" note and never block manual correction. Interaction/warning data is surfaced, not hidden.
- **Production hardening:** offline path (APIs fail → local + AI-from-knowledge still work), empty states, loading/streaming states, error toasts, no force-unwraps on network JSON, `saveOrLog` for all writes, full accessibility (Dynamic Type, VoiceOver labels, 44pt targets), and no regressions in Schedule/Meals/Protocol/Wellness.

### 2.4 Version bump + update flow
- **Bump `ProtocolSubApp.version` and `NutritionSubApp.version`** from the default to a new explicit value (e.g. `"1.1.0"` — minor, since this is additive new capability). Declare `var version` explicitly on both (mirror how `NotesSubApp` declares it).
- If the new `CustomProductInfo` model needs any backfill, implement it in the sub-app's `migrate(from:to:context:)` hook (default no-op otherwise). Adding a brand-new model is non-destructive, so `updateNeedsConfirmation` stays `false` unless a real data migration is introduced.
- Record the bump so `SubAppRegistry.availableUpdate`/`ModuleUpdatesView` surface it, and the Coach `list_module_updates`/`update_module` tools see it.

### 2.5 Brain reach (Coach)
- Add Coach tools so the brain can do what the UI does: `search_product` (the unified engine; returns structured results + whether it was persisted) and `log_meal` (create a `MealLog`, optionally via `estimateMeal`). `create_or_update_medication` already exists for adopting into the protocol. Reads ungated; writes gated by `writeToolsEnabled`; destructive ops use `PendingAction`. Register in `ToolRegistry` and **teach each in `CoachPromptBuilder`**.

### 2.6 Shared principles
- Prefer extending `ProductSearchService` + the knowledge enums + `SubApp`/`SubAppRegistry` over new parallel managers.
- Additive SwiftData only; new model + optional/defaulted fields; tolerant decoders.
- All Coach reads go through tools + shared helpers; UI reads use `@Query`/`FetchDescriptor`.

---

## 3. Roadmap (ordered; each item is one safe, shippable iteration)

**Phase A — Persistence + version foundation (low risk, unblocks everything)**
- A1. Add the `CustomProductInfo` `@Model` (mirror `SupplementInfo` fields + `category`, `source`, `isAIGenerated`, `citations`, `createdAt`). Register it in `ModelContainerFactory` and add it to a sub-app's `models`. Build green; no UI/behavior yet.
- A2. Add a persistence + lookup façade: a way to save a discovered profile as `CustomProductInfo` (de-dupe by normalized name/aliases) and to read them back. Make the local lookup (`SupplementKnowledge.find`/`fuzzyMatch` or a new façade used by `ProductSearchService` + the add-sheet autocomplete) also consult `CustomProductInfo`.
- A3. Bump `ProtocolSubApp.version` and `NutritionSubApp.version` to `"1.1.0"` (explicit `var version`). Verify `availableUpdate`/`ModuleUpdatesView` surface the bump for an existing install; add a no-op `migrate` unless backfill is needed. Add a test for the version compare.

**Phase B — Unified search engine (the Perplexity core)**
- B1. Add the **AI research pass** to `ProductSearchService` as the final tier: an `AIService`-backed researcher that returns a structured profile (typed decode) with citations + `isAIGenerated`. Prefer hosted `web_search` grounding; degrade gracefully to AI-from-knowledge if web search is unavailable. Normalize into the unified result type. Unit-test the parse/normalize.
- B2. Wire **persist-on-discovery**: when B1 (or an accepted API result) yields a profile not already local, save a `CustomProductInfo` (via A2) so the next search is instant. Return whether it was persisted.
- B3. Make `ProductSearchService.search` the single engine used by the add-protocol flow (replace the bespoke `aiSearchIngredient` path with the unified engine; keep autocomplete + manual entry).

**Phase C — Search UI (AI-first surface)**
- C1. A search field + streaming result list in the Protocol section: result cards with source badge, benefit/mechanism/dose/timing/warnings, citations, AI-generated disclaimer, and "Add to protocol". Design-system styled, accessible.
- C2. Extend the same engine + result UI to **Meals** (food search via Open Food Facts + AI), with "Log meal" prefilled from the result, plus NL meal capture.
- C3. Route label scan (`scanProtocolLabel` / `ProductScanView` / `MealScanView`) through the unified engine + persistence so scanned-but-unknown items get researched and saved.

**Phase D — Coach reach**
- D1. Add `search_product` Coach tool (unified engine; returns structured results + persisted flag). Register + teach it.
- D2. Add `log_meal` Coach tool (create `MealLog`, optional `estimateMeal`). Register + teach it. Confirm `create_or_update_medication` adopts a searched item cleanly.

**Phase E — Production hardening + polish**
- E1. Offline/empty/error/loading states across search, scan, meals, protocol; remove force-unwraps on network JSON; `saveOrLog` everywhere; verify no crashes on bad/timeout responses.
- E2. Accessibility pass (Dynamic Type, VoiceOver, 44pt) on all new + touched tracker surfaces; de-dupe/cleanup persisted catalog (merge aliases, avoid duplicates).
- E3. Tests: search tiering + AI parse + de-dupe persistence + meal NL parse + version compare; a final full-module smoke pass (Schedule/Meals/Protocol/Wellness all work without bugs).

## 4. THE LOOP PROMPT (paste this each session)

```
You are continuing a long-running project to make PulseLoop's Tracker module
(food/meals, medications, supplements, vitamins, peptides) comprehensive,
AI-first, and production-ready: a Perplexity-style search engine that finds
anything not already in the database, has the AI synthesize a structured profile,
and SAVES it to the database for reuse. Your single source of truth is
docs/TRACKER_LOOP_PROMPT.md (mission §0, code anchors §1, architecture §2,
roadmap §3, guardrails §5) and the live tracker docs/TRACKER_PROGRESS.md.

Do EXACTLY ONE iteration, then stop. Follow this loop:

1. ORIENT. Read docs/TRACKER_LOOP_PROMPT.md and docs/TRACKER_PROGRESS.md. If
   TRACKER_PROGRESS.md does not exist, create it from the §3 roadmap with every
   item set to "pending", then treat iteration A1 as current.

2. SELECT. Pick the single highest-priority "pending" iteration (top-to-bottom in
   §3). Restate it in one sentence. If it is too big for one safe, shippable step,
   split it: do the first sub-step now and add the remainder as new pending items.

3. PLAN. Write a short todo list for this iteration only. Verify the exact real
   files/types from §1 by reading them — never invent file paths, model fields,
   tool names, or APIs. Confirm the real ProductSearchService API, SupplementInfo /
   PeptideInfo / FDADrugResult / OpenFoodFactsProduct shapes, AIService.complete /
   stream signatures, WebSearchTool spec, Medication / MealLog models,
   ProtocolTools names, and the SubApp / SubAppRegistry / SemanticVersion API
   before using them.

4. IMPLEMENT. Make the change, reusing existing patterns:
   - SEARCH work: extend ProductSearchService into the one tiered engine (local
     catalogs incl. CustomProductInfo -> Open Food Facts + openFDA -> AI research
     pass). The AI pass returns a TYPED structured profile with citations +
     isAIGenerated; prefer hosted web_search grounding (WebSearchTool); degrade
     gracefully offline. Normalize all tiers to one result type with a source badge.
   - PERSISTENCE work: discovered/accepted profiles not already local are saved as
     CustomProductInfo (@Model), de-duped by normalized name/aliases, and flow back
     into find/fuzzyMatch/autocomplete. Additive SwiftData only; register new models
     in ModelContainerFactory and on a sub-app's models.
   - UI work: AI-first search/scan/NL-capture surfaces with manual entry as fallback;
     result cards show benefit/mechanism/dose/timing/warnings/citations + an
     "AI-generated, verify with a professional" note; one-tap adopt into protocol
     (Medication) or meal log (MealLog).
   - New Coach tools: enum XTools { static var all/readTools/writeTools } via
     AnyCoachTool.make(...); reads ungated, writes gated (writeToolsEnabled);
     destructive ops queue a PendingAction confirm card. Register in ToolRegistry
     and TEACH each in CoachPromptBuilder.systemPrompt — an untaught tool is wasted.
   - VERSIONING: bump ProtocolSubApp/NutritionSubApp version explicitly; use the
     existing SubApp/SubAppRegistry/SemanticVersion update flow; migrations are
     additive + data-preserving (default no-op migrate unless backfill is needed).
   - Data: additive SwiftData only (new models, optional/defaulted fields, tolerant
     decoders). NEVER drop or corrupt meals, meds, or logs.
   - Design system is law: PulseColors/PulseFont/PulseRadius/PulseLayout, components
     from AppTheme.swift + Components.swift, .cursor/rules/design-system.mdc. SF
     Symbols only, no emoji in UI, primary buttons black, accent sparingly.

5. VERIFY. Build and resolve errors before finishing:
   xcodebuild -project PulseLoop.xcodeproj -scheme PulseLoop \
     -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
   Run ReadLints on edited files. Add/adjust tests where §3 calls for them. The app
   MUST build at the end of the iteration.

6. RECORD. Update docs/TRACKER_PROGRESS.md: mark this iteration done with a 1–3 line
   summary (what changed + which files + any new models/fields/tools/flags), list any
   follow-ups you spun off, and clearly name the NEXT pending iteration.

7. STOP. Post a concise summary: what you did, build status, the next iteration. Do
   not start the next iteration. Do not create a git commit unless I ask.

Rules of engagement:
- Keep the build green; never leave a broken state.
- Prefer small, reversible steps; add models/fields/tools additively so old paths
  keep working and old meals/meds/logs keep loading.
- AI-first, not AI-only: manual entry and the existing add-sheets always remain.
- Health domain = be careful: label AI/web profiles as AI-generated, surface
  warnings/interactions, never present invented dosing as authoritative advice.
- Every new Coach tool gets a system-prompt usage line.
- The module version MUST be bumped as part of this project (Phase A3) and recorded.
- If a decision has real product trade-offs (result type shape, when to persist,
  how to ground the AI pass, food vs drug routing, what counts as low-confidence),
  state your default, proceed, and note it in the tracker rather than blocking.
- If you find the roadmap is wrong, propose the fix in the tracker and adjust, but
  still complete one concrete shippable step this iteration.
```

---

## 5. Guardrails (referenced by the loop — the hard rules)

- **Build green every iteration.** End state compiles and runs; Xcode build + ReadLints are the gate.
- **Data integrity above all.** Additive, lightweight SwiftData only (new `CustomProductInfo` model; new fields optional/defaulted with tolerant decoders). **Never drop or corrupt user meals, meds, or logs.** Register every new `@Model` in `ModelContainerFactory` and on a sub-app's `models`.
- **One search engine.** Extend `ProductSearchService` + the knowledge enums. Do not fork a second product-search path. All tiers normalize to one result type.
- **Persist what you discover.** AI/web/API profiles not already local are saved as `CustomProductInfo`, de-duped, and fed back into lookup/autocomplete — no re-querying the same item.
- **AI-first, not AI-only.** The manual `addProtocolSheet`/`addMealSheet` forms always remain working fallbacks.
- **Health-domain safety.** AI-synthesized profiles are clearly labeled AI-generated with a "verify with a professional" disclaimer; interactions/warnings are surfaced; never present invented dosing as authoritative medical advice.
- **One versioning system.** Bump `ProtocolSubApp`/`NutritionSubApp` versions and ship via the existing `SubApp`/`SubAppRegistry`/`SemanticVersion` update flow (mirror `NotesSubApp`'s explicit `var version`). Module updates run forward-only, data-preserving migrations; risky/uncertain migrations confirm first and never wipe.
- **Teach every Coach capability.** A tool not described in `CoachPromptBuilder.systemPrompt` does not exist to the brain. Destructive Coach writes use the `PendingAction` confirm card; reversible writes apply immediately.
- **Deterministic, safe data access.** Coach reads go through tools + shared helpers; no ad-hoc queries scattered in handlers. No arbitrary code execution. No force-unwraps on network JSON.
- **Resilience.** Network tiers fail gracefully (offline → local + AI-from-knowledge still return something); empty/loading/error states everywhere; reuse `NetworkRetry` + `ResponseCache`.
- **Design system is law.** `PulseColors`/`PulseFont`/`PulseRadius`/`PulseLayout` + components from `App/AppTheme.swift` + `DesignSystem/Components.swift`; obey `.cursor/rules/design-system.mdc`. SF Symbols only (no emoji in rendered UI). Primary buttons black, accent sparingly, hairline-bordered cards, calm whitespace.
- **Security.** No API keys/secrets in source; Keychain only via `AIService`.
- **Accessibility & quality.** Maintain Dynamic Type, VoiceOver labels, and 44pt tap targets on every new surface; add tests for search tiering/AI-parse/persistence-dedupe/meal-NL-parse/version-compare.
- **One iteration at a time.** A single shippable step, then stop — keeping the project reviewable.
