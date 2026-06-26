# PulseLoop → Comprehensive Travel Module + In-Chat Travel Cards + Health Sync — Loop Prompt

> **How to use this file.** Paste the section titled **"THE LOOP PROMPT"** (§4) into the agent as a single
> message at the start of each working session. The agent picks up the roadmap, does **exactly one iteration**,
> updates the tracker (`docs/TRAVEL_PROGRESS.md`), and stops. Re-run to advance the next iteration. Everything
> else here (persona, mission, anchors, roadmap, guardrails) is reference material the prompt points at.

---

## 0. Operating Persona (who "you" are every iteration — never changes)

You operate as a **founder-led team of 10 senior engineers + designers** shipping a consumer-grade product a
Fortune-500 would be proud to launch. Embody the whole team's judgment in every iteration:

- **2 × iOS/SwiftUI engineers** — own the Travel UI/UX, in-chat cards, design-system fidelity, navigation, a11y.
- **1 × AI/agent engineer** — owns the Coach orchestrator, the strict response schema, the travel result cards,
  tool routing, and module-aware behavior.
- **2 × backend engineers** — own the `web/` Next.js OpenRouter proxy, credits, and any sync/data contracts.
- **1 × data/integrations engineer** — owns connectors (HealthKit, ring BLE, cloud sync) and the new Fitbit +
  Google health source integrations (OAuth2 + REST).
- **1 × design-systems engineer** — guards `PulseColors`/`PulseFont`/`PulseCard` parity; makes Travel beautiful.
- **1 × platform engineer** — owns `SubApp`/`SubAppRegistry`, routes, versioning, additive migrations.
- **1 × QA engineer** — owns unit/smoke coverage and empty/loading/error states.
- **1 × tech lead / founder** — sequences work, enforces guardrails, keeps `main` green, calls trade-offs.

**How the team works:** small reversible steps; design before code on anything ambiguous; the app **always builds
and runs** at the end of an iteration; every surface obeys the design system; no secrets in source; sub-apps stay
declarative. When a decision has real product trade-offs, the tech lead states a default, proceeds, and records it
in the tracker for review rather than blocking. **Aim high: this is a flagship module people would choose the app
for, not a CRUD demo.**

---

## 1. North-Star Vision (the fixed mission)

Make **Travel** the flagship module of PulseLoop — a comprehensive, genuinely delightful trip planner that people
*want* to use — and prove the app's thesis that **everything interconnects** and the **assistant is the engine**.
Deliver four initiatives to completion:

### Initiative 1 — A comprehensive, beautiful Travel sub-app
A trip is more than a list of links. Build a Travel module that covers the real journey end-to-end:
- **Rich trip model**: destination(s), origin, dates, travelers, budget + live cost rollup, cover image, status.
- **Itinerary by day**: a day-by-day timeline (flights, lodging, activities, restaurants, transport, notes) with
  times, locations, prices, booking links, and a "booked/idea/confirmed" state per item.
- **Maps**: a per-trip map showing saved places (lodging, activities, restaurants) with pins; tappable.
- **Budget**: per-category spend, total estimated vs. booked, currency-aware.
- **Documents/notes**: confirmation numbers, packing notes, reservations.
- **Polished UI**: a trips home (upcoming / past), a trip detail with header + cover + day timeline + map + budget;
  empty/loading states that point back to the assistant; design-system-correct throughout. **No fake data.**

### Initiative 2 — Travel results live IN the chatbox
When the user plans travel in chat, the assistant must render **real, structured travel result cards inline in the
conversation** (not a wall of text, and not only on a separate screen):
- **Flight cards, hotel/stay cards, activity/restaurant cards, and an itinerary/day card** rendered as first-class
  card types in the Coach response (alongside the existing chart/diagram/media cards).
- Each result card shows the essentials (title, price, time/location, rating/why-it's-good, thumbnail/map when
  available) and a **"Save to trip"** affordance that persists it as a `TripItem` (reusing the confirm/apply path).
- The same data renders identically whether it appears in chat or on the Travel screen (one shape, two surfaces).

### Initiative 3 — Everything interconnects
Travel is wired into the rest of the life-OS so a trip pulls the whole app together:
- **Tasks**: "create my pre-trip checklist" → tasks linked to the trip (passport, packing, currency), shown on the
  trip and in Tasks.
- **Day Plan / calendar**: trip items with times surface on the relevant days in the Day Plan / Home calendar.
- **Notes**: trip notes link to the trip; the assistant can attach a note to a trip.
- **Finance/budget**: trip costs roll up; if a finance surface exists, expenses can reference a trip.
- **Health**: on a health topic only, the assistant can use trip context (e.g. jet-lag / time-zone guidance) — but
  Travel never force-pivots to health (honor the existing topic-discipline rule).
- Cross-links use the established **UUID-foreign-key** convention (additive, defaulted, lightweight migration).

### Initiative 4 — Sync with Google & Fitbit health data
Add the ability to pull health/activity data from **Fitbit** and **Google** in addition to Apple Health + the ring:
- Implement them as additional **`WearableDataSource`** providers feeding the **same** `Measurement` / `ActivityDaily`
  / `SleepSession` stores, so existing cloud sync uploads them automatically.
- **Fitbit Web API** (OAuth2 + REST) and **Google Fit REST API** (OAuth2) are the realistic iOS paths. **Note:**
  Android "Health Connect" is an Android-only API and cannot run in this iOS app — treat "Google Health" as Google
  Fit REST on iOS and record this constraint in the tracker. (A future Android client could use Health Connect.)
- Honest connector UX in `ConnectAccountsView`: real connected/last-synced/error/needs-auth states — never a fake
  "connected". OAuth tokens live in the Keychain (never in source).

**Non-negotiables (every iteration):**
- App **always builds and runs**; `web/` always `next build` + `eslint` clean when touched.
- **Design system is law** (`.cursor/rules/design-system.mdc`): SF Symbols only, no emoji in UI, primary buttons
  black, hairline-bordered cards, calm whitespace.
- **No secrets in source.** Provider = **OpenRouter**. iOS/OAuth secrets live in the Keychain.
- **Honest UX.** Never show a connected/synced/booked state that isn't real.
- **Additive SwiftData migrations** — defaulted new fields, never drop user data.
- **Declarative, schema-driven cards** — extend the strict `CoachResponse` schema; never eval arbitrary code/HTML.

---

## 2. Codebase Context (real anchors — verify by reading; do not invent paths)

**iOS app** — SwiftUI + SwiftData. Entry `PulseLoop/PulseLoopApp.swift` → `RootAppView` (`PulseLoop/Views/RootViews.swift`).
Design system: `PulseLoop/App/AppTheme.swift` (`PulseColors`, `PulseFont`, `PulseRadius`, `PulseLayout`,
`PulseCard`, `StatusChip`/`ChipStyle`) + `PulseLoop/DesignSystem/Components.swift`. Rule: `.cursor/rules/design-system.mdc`.

**Travel module (already partially built — extend, don't rebuild):**
- Models: `PulseLoop/Models/TravelModels.swift` — `@Model Trip`, `@Model TripItem`, `TripStatus`,
  `TripItemKind` (`flight, lodging, activity, restaurant, transport, note`). `Trip.items` is the only intra-module
  `@Relationship` (cascade). `Trip`/`TripItem` are in `coreModels` (`PulseLoop/Persistence/ModelContainerFactory.swift`),
  so any module can fetch them with no schema change.
- Tools: `PulseLoop/Coach/Tools/TravelTools.swift` — `list_trips`, `get_trip`, `create_trip`, `update_trip`,
  `add_trip_item`, `update_trip_item`, `set_trip_item_booked`, `delete_trip_item`. Reads always on; writes gated by
  `flags.writeToolsEnabled`. Destructive writes queue a `PendingAction` confirm card.
- UI: `PulseLoop/Views/TravelView.swift` — `TravelView` (trips list) + `TripDetailView` (sections by kind) +
  `TripCard`/`TripItemRow`. Currently basic; this is the surface to make comprehensive.
- SubApp: `PulseLoop/Platform/SubApps/TravelSubApp.swift` (contributes models + `aiTools`). Registered as
  `.travel: TravelSubApp()` in `PulseLoop/Platform/SubAppRegistry.swift`.
- Module metadata: `AppModule.travel` in `PulseLoop/App/AppTheme.swift` (name "Travel", icon `airplane`, color
  `.teal`, description). Routes `AppRoute.travel` / `AppRoute.tripDetail(UUID)` resolved in the central switch
  `destinationView(for:)` in `PulseLoop/Views/RootViews.swift` (NOT yet via the per-subapp `SubAppRouter`).
- `navigate_to`: `PulseLoop/Coach/Tools/PlatformControlTools.swift` `destinations` dict maps `"travel" → (nil, .travel)`.
  There is **no** `trip_detail` deep-link yet (the dict maps to static routes, no id).
- Tests: `PulseLoopTests/TravelToolsTests.swift` (4 tests: create → add items → read → booked → archive + gating).

**Coach response cards (how to render travel results in chat):**
- Schema model: `PulseLoop/Coach/Schema/CoachResponse.swift` — `struct CoachResponse` with fields `responseType`,
  `title`, `summary`, `bullets`, `chart: CoachChart?`, `diagram: CoachDiagram?`, `media: [CoachMedia]`,
  `followUpChips: [String]`, `sources`, `actionsTaken`, `confidence`, plus a lenient forward-compat `cards: [CoachCard]`.
  Encode/decode via `encodedJSON()` / `decode(fromJSON:)`; `adaptiveShaped()` strips a stray chart off non-chart replies.
- **Strict JSON schema**: `PulseLoop/Coach/Schema/CoachResponseSchema.swift` — `strict: true`,
  `additionalProperties: false`, and **every property must appear in the top-level `required` array** (OpenAI strict
  mode). `diagramSchema` (nullable object) and `mediaSchema` (array) are the templates for a new card field.
- Card views: `PulseLoop/Coach/Schema/CoachResponseView.swift` is the declarative catalog (renders each field's view
  in order, plus the `followUpChips` capsule row → `onChipTap` → `send(chip)`). Per-card views are siblings:
  `CoachChartView.swift`, `CoachDiagramView.swift`, `CoachMediaCardView.swift` (best rich-card template). Confirm
  cards: `CoachActionCardView.swift`.
- Persistence: the **whole** `CoachResponse` is JSON in `CoachMessage.cardsJSON` (`PulseLoop/Models/PulseModels.swift`),
  decoded at render in `CoachView.swift` (`CoachBubble.structured`). **No SwiftData migration needed** for new card
  fields — they ride along in the JSON.
- Orchestrator: `PulseLoop/Coach/Orchestration/CoachOrchestrator.swift` (`textFormat = CoachResponseSchema.textFormat`,
  tool loop, `parseFinal`). Tools: `PulseLoop/Coach/Tools/` (`AnyCoachTool.make`, `ToolRegistry`, `ToolExecutionContext`,
  `PendingAction`). **Card emission pattern = "prepare → copy verbatim"**: e.g. `DiagramTools.prepareDiagram` returns
  `.encoding(Prepared{ diagram, note: "Copy this … verbatim into the final response's `diagram` field." })`. Mirror it
  for travel cards. Prompt: `PulseLoop/Coach/Context/CoachPromptBuilder.swift` (when to call prepare-tools + which field
  to copy into).
- ⚠️ Verify whether `TravelTools` is registered in `ToolRegistry.init` (it may only be contributed via
  `TravelSubApp.aiTools` when the module is installed). Confirm the travel tools actually reach the model.

**Health sources / sync (for Fitbit + Google Fit):**
- Metric model: `PulseLoop/Models/PulseModels.swift` — `@Model Measurement` (`kind`, `value`, `unit`, `timestamp`,
  `source`); `MeasurementKind` today is only `hr`/`spo2`; `MeasurementSource` = `ring/mock/history/workout/manual/live`.
  Steps → `ActivityDaily`, sleep → `SleepSession` (same file). **These two enums + `CloudSyncService.webKind(for:)` are
  the hard gating points** if you add kinds/sources — extend them additively.
- Data-source protocol: `PulseLoop/Services/HealthKitIngestion.swift` defines `protocol WearableDataSource`
  (`sourceName`, `requestAuthorization`, `fetchLatestHeartRate`, `fetchLatestSpO2`, `fetchSteps(for:)`,
  `fetchSleep(for:)`). **Only `HealthKitIngestion` conforms today** — make it actually polymorphic with a small registry.
- Cloud sync: `PulseLoop/Services/CloudSyncService.swift` — `sync(context:days:)` enumerates `Measurement`s and POSTs to
  `api/ingest/metrics` with `clientId = row UUID` (idempotent), gated consent → configured → paired(token). Web side
  `web/src/app/api/ingest/metrics/route.ts` accepts **any** `kind` string → no web schema change for new kinds.
- Connector UI: `PulseLoop/Views/ConnectAccountsView.swift` (the "MORE WEARABLES" section has Oura/Whoop/Garmin
  `.unavailable` placeholders — where Fitbit/Google rows become real); status model `ConnectorStatus`
  (`.connected/.syncing/.lastSynced/.error/.unavailable`) + `ConnectorStatusPill`.
- Token storage: `protocol APIKeyStore` (`PulseLoop/Coach/Config/OpenAIKeychainStore.swift`); copies
  `CloudSyncKeychainStore`/`MuapiKeychainStore`. OAuth needs a **token bundle** (access + refresh + expiry) — store a
  JSON blob, not a single string. **No existing OAuth helper** — `ASWebAuthenticationSession` is the path (net-new).

**Cross-module data (for interconnection):**
- All `@Model`s share one flat SwiftData schema (`ModelContainerFactory`). Cross-links = **store a foreign UUID** on
  the referencing model (no cross-module `@Relationship`s). Precedent: `Note.linkedTaskId`/`linkedNoteIds` in
  `PulseLoop/Models/LifeOSModels.swift`. `TaskItem`, `DayPlanAction`, `Note` live here; `DayPlanAction` has no entity FK
  today. There is **no** real Finance module (only `Subscription` + a UI-only `ExpenseEntry`).
- Home feed: `PulseLoop/Views/HomeView.swift` uses a hardcoded `HomeModule` enum (no `travel` case today). The
  forward-looking seam is `SubApp.dashboardCard(context:)` (`PulseLoop/Platform/SubApp.swift`), not yet used by any module.

**Web backend** — `web/` (Next.js 16 / Drizzle / Neon / Clerk). Coach routes `web/src/app/api/v1/coach/responses/route.ts`
(device) + `coach/web/route.ts` (Clerk), OpenRouter via `web/src/lib/openrouter.ts`. Credits `web/src/lib/credits.ts`
(note: `CREDITS_UNLIMITED` flag currently on). Web Travel parity is **optional / lowest priority** here (iOS-first).

---

## 3. Phased Roadmap (ordered backlog — work top-to-bottom)

Track status in `docs/TRAVEL_PROGRESS.md` (create on T1 if missing). Each iteration is small, shippable, and leaves
the iOS app (and web, if touched) building. Tracks run **T (model) → C (cards in chat) → X (interconnect) →
H (health sync) → Q (hardening)**. Reorder only with a tracker note explaining the dependency.

### Track T — Comprehensive Travel sub-app (Initiative 1)
- **T1.** Design doc in the tracker: the target Trip data model (travelers, budget/currency, cover image, multi-city,
  documents), the trip-detail layout (header+cover → day timeline → map → budget → linked tasks/notes), and the
  empty/loading states. Audit what `TravelModels`/`TravelView`/`TravelTools` already do vs. the target. No code beyond
  the doc + any trivial scaffolding.
- **T2.** Extend `Trip`/`TripItem` models **additively**: e.g. `Trip.travelerCount`, `Trip.budgetAmount`/`budgetCurrency`,
  `Trip.coverImageURL`, `TripItem.rating`, `TripItem.latitude`/`longitude`, `TripItem.confirmationNumber`, an
  `idea/saved/booked` state if richer than the current `booked: Bool`. All optional + defaulted (lightweight migration).
  Update `TravelTools` create/add/update tool schemas to read/write the new fields. Keep `TravelToolsTests` green.
- **T3.** Rebuild `TripDetailView` into a real itinerary: a **day-by-day timeline** (grouped by `dayOffset`/date, ordered
  by time), each item a polished row with icon, time, price, location, booking link, booked toggle. Cover header with
  destination, dates, travelers, status, and a **live budget rollup** (sum of item prices by category, est. vs. booked).
- **T4.** Add a **trip map**: a MapKit map on the trip detail showing pins for items with coordinates (lodging,
  activities, restaurants); tapping a pin highlights the item. Geocode saved items lacking coordinates (best-effort,
  cached on the item). Design-system-correct, with a graceful no-coordinates empty state.
- **T5.** Rebuild `TravelView` (trips home): upcoming vs. past sections, rich `TripCard` (cover, dates, item counts,
  budget, status chip), and a clear empty state pointing to the assistant. Add a "New trip" affordance that hands off to
  the assistant (or a minimal manual create).
- **T6.** Routing polish: add a `trip_detail` deep-link to `navigate_to` (accept an optional trip id → `.tripDetail(uuid)`)
  so the assistant can open a specific trip; optionally move Travel routes into `TravelSubApp.registerRoutes` via a
  `TravelRoute`. Add Travel to the Home feed (either a `HomeModule.travel` card or implement
  `TravelSubApp.dashboardCard` and render installed sub-apps' cards) showing the next upcoming trip.
- **T7.** Travel QA pass: extend `TravelToolsTests` for the new fields + budget rollup logic + map coordinate handling;
  smoke the detail/list states (empty/loading/populated).

### Track C — Travel results in the chatbox (Initiative 2)
- **C1.** Define the in-chat travel card model: a new file `PulseLoop/Coach/Schema/CoachTravelCard.swift` — a `Codable`
  `CoachTravelCard` (kind: flight/stay/activity/restaurant/transport; title, subtitle, price+currency, time/location,
  rating, thumbnailURL, bookingURL, lat/lon) and a `CoachItineraryDay` for day grouping. Lenient `init(from:)`, snake_case
  CodingKeys. Decide single vs. array (array recommended: `travelCards: [CoachTravelCard]`, plus optional
  `itinerary: [CoachItineraryDay]`). Make them `Identifiable`.
- **C2.** Add the fields to `CoachResponse` (var + CodingKeys + init default + `decodeIfPresent`) **and** to the strict
  schema in `CoachResponseSchema.swift` (new sub-schemas modeled on `mediaSchema`/`diagramSchema`, added to top-level
  `properties` **and** `required`). Keep the existing strict-mode tests/flows green (every property in `required`).
- **C3.** Build the SwiftUI card views: `PulseLoop/Coach/Schema/CoachTravelCardView.swift` — a flight card, a stay card,
  an activity/restaurant card, and an itinerary-day list, styled like `CoachMediaCardView` (rounded 16, `PulseColors`,
  hairline border, AsyncImage thumbnail, price, a `Link` to the booking URL, optional inline `Map` for a card with
  coordinates). Render them in `CoachResponseView` alongside the existing card blocks.
- **C4.** "Save to trip" from a chat card: a button on each travel card that persists it as a `TripItem` (into the active
  or a chosen trip), reusing the `PendingAction`/`CoachViewModel`/`PendingActionExecutor` confirm-apply path (or directly
  calling `add_trip_item`). Honest confirmation that it was saved; the same item then appears on the Travel screen.
- **C5.** Emit cards from a tool + prompt: add a `prepare_travel_cards` tool (in `TravelTools`) returning
  `.encoding(Prepared{ travelCards/itinerary, note: "Copy verbatim into the response's `travel_cards`/`itinerary` field" })`,
  register it so it reaches the model, and update `CoachPromptBuilder` to tell the assistant: when planning travel,
  web_search real options then produce travel cards inline (and save the chosen ones to a Trip). One shape, two surfaces.
- **C6.** Chat-cards QA pass: a test that a travel-planning response decodes the new card fields and that the schema stays
  strict-valid; snapshot the "save to trip" path persists a `TripItem`.

### Track X — Everything interconnects (Initiative 3)
- **X1.** Add cross-link FKs (additive, defaulted): `TaskItem.tripId: UUID?`, `Note.linkedTripId: UUID?`,
  `DayPlanAction.entityType: String?` + `entityId: UUID?` (so a plan action can point at a `TripItem`). Lightweight
  migration; update any initializers.
- **X2.** Trip → Tasks: a tool/flow ("create my pre-trip checklist") that creates `TaskItem`s stamped with `tripId`
  (passport, packing, currency, check-in). Render linked tasks on `TripDetailView`; show the trip on those tasks.
- **X3.** Trip → Day Plan / calendar: surface trip items with times on the relevant days in the Day Plan / Home calendar
  by reading `TripItem.startAt`/`dayOffset`; deep-link a plan entry back to the trip item.
- **X4.** Trip → Notes + budget: let the assistant attach a `Note` (`linkedTripId`) to a trip and show it on the detail;
  expose the trip budget rollup (and, if/when a finance surface exists, let expenses reference `tripId`).
- **X5.** Assistant cross-domain awareness: update `CoachPromptBuilder` so a trip can pull the app together (offer to
  create the checklist, add to calendar, take notes) **without** force-pivoting to health — honor topic discipline.
- **X6.** Interconnect QA pass: tests for the FK links (task↔trip, note↔trip, dayplan↔tripitem) and the checklist flow.

### Track H — Sync with Google & Fitbit (Initiative 4)
- **H1.** Design doc in the tracker: the multi-source health architecture. Make `WearableDataSource` polymorphic via a
  small registry; decide the OAuth token-bundle Keychain shape; extend `MeasurementKind` (e.g. `steps`, `sleep`, `hrv`,
  `restingHR`) + `MeasurementSource` (`.fitbit`, `.googleFit`) + `CloudSyncService.webKind(for:)` additively. **Record
  the Health Connect = Android-only constraint** (iOS path = Google Fit REST; Health Connect deferred to a future Android
  client).
- **H2.** OAuth2 infrastructure: an `OAuthTokenStore` (Keychain JSON token bundle: access/refresh/expiry) + a reusable
  `ASWebAuthenticationSession` authorization-code flow helper (PKCE), with redirect handling. No secrets in source
  (client ids via config/Keychain). Net-new, small, well-tested.
- **H3.** Fitbit source: `FitbitIngestion: WearableDataSource` — OAuth connect, then REST fetch of HR/steps/sleep/(SpO₂),
  mapping JSON → `Measurement`/`ActivityDaily`/`SleepSession` with `source = .fitbit`. Token refresh on expiry.
- **H4.** Google Fit source: `GoogleFitIngestion: WearableDataSource` — OAuth connect + REST fetch mapping to the same
  stores with `source = .googleFit`. (Document the Health Connect caveat in-code.)
- **H5.** Connectors UI: promote the placeholder rows in `ConnectAccountsView` to real Fitbit + Google rows backed by
  `ConnectorStatus.forFitbit`/`.forGoogleFit` (connect / connected / last-synced / needs-auth / error), with a working
  "Import now". Imported metrics flow through the existing `CloudSyncService` automatically.
- **H6.** Health-sync QA pass: tests for the source→model mapping, token-bundle store, `webKind` for new kinds, and the
  connector status mapping. Mock the REST transport (no live network in tests).

### Track Q — Final hardening
- **Q1.** Cross-initiative polish: accessibility (Dynamic Type, VoiceOver, 44pt targets), consistent empty/loading/error
  states across Travel + chat cards + connectors, performance of the map/timeline, and a release-readiness note in the
  tracker. Optional: a thin web Travel read-only surface for parity (only if time remains).

---

## 4. THE LOOP PROMPT (paste this each session)

```
You are a founder-led team of 10 senior engineers + designers (persona §0) building PulseLoop's flagship TRAVEL
experience: a comprehensive Travel sub-app, real travel result cards rendered IN the chatbox, deep interconnection
with the rest of the app, and health sync with Google (Google Fit REST) + Fitbit. Your single source of truth is
docs/TRAVEL_LOOP_PROMPT.md (persona §0, mission §1, code anchors §2, roadmap §3, guardrails §5) and the live tracker
docs/TRAVEL_PROGRESS.md.

Do EXACTLY ONE iteration, then stop. Follow this loop:

1. ORIENT. Read docs/TRAVEL_LOOP_PROMPT.md and docs/TRAVEL_PROGRESS.md. If the tracker doesn't exist, create it from
   the §3 roadmap with every item "pending", then treat T1 as current.

2. SELECT. Pick the single highest-priority "pending" iteration (top-to-bottom across tracks T → C → X → H → Q,
   unless the tracker notes a dependency reordering). Restate it in one sentence. If it's too big for one safe
   shippable step, split it: do the first sub-step now and add the remainder as new pending items.

3. PLAN. Write a short todo list for THIS iteration only. Name the exact real files from §2 you'll touch — verify by
   reading them first; never invent paths.

4. IMPLEMENT. Build it as the whole team would: correct, beautiful UI/UX AND a sound data path. Reuse existing
   patterns — the iOS design system (PulseColors/PulseFont/PulseCard/StatusChip, .cursor/rules/design-system.mdc),
   the Coach strict-JSON response schema + card catalog + "prepare → copy verbatim" tool pattern, the
   PendingAction confirm/apply path, the SubAppRegistry, the WearableDataSource seam, and the UUID-foreign-key
   cross-link convention. SF Symbols only, no emoji in UI, primary buttons black, no secrets in source, OpenRouter
   (never OpenAI) in web, honest connector/booked/synced state (never faked). Additive SwiftData migrations only.

5. VERIFY. Build before finishing and resolve errors:
   - iOS:  xcodebuild -project PulseLoop.xcodeproj -scheme PulseLoop \
             -destination 'platform=iOS Simulator,id=CFAB47DC-4676-469B-AA5F-29EED5A93200' \
             -derivedDataPath build build
           (run on the booted simulator when a UI change benefits from it).
   - web (if touched): npm run build && npm run lint  (in web/).
   Use ReadLints on edited files. Add/adjust tests where §3 calls for a QA pass. Everything MUST build at the end.

6. RECORD. Update docs/TRAVEL_PROGRESS.md: mark the iteration done with a 1–3 line summary + touched files, list any
   follow-ups you spun off, and clearly name the NEXT pending iteration.

7. STOP. Post a concise summary: what you did, build status, and the next iteration. Do not start the next one. Do
   not create a git commit unless explicitly asked.

Rules of engagement:
- Keep main always building; never leave a broken state. Prefer small reversible steps; use adapters so old and new
  paths coexist during a migration.
- Backward-compatible, additive SwiftData migrations only — defaulted new fields, never drop user data.
- One card SHAPE, two surfaces: a travel result looks the same in chat and on the Travel screen.
- Land everything on iOS first (primary surface). Web Travel parity is optional/lowest-priority (Track Q).
- "Google Health" on iOS = Google Fit REST (OAuth2). Android Health Connect is out of scope for this iOS target —
  note it, don't attempt it.
- If a decision has real product trade-offs, state your default, proceed, and note it in the tracker rather than
  blocking. If the roadmap is wrong, fix it in the tracker — but still ship one concrete step this iteration.
```

---

## 5. Guardrails (the hard rules the loop enforces)

- **Build green every iteration.** iOS must compile/run; web must `next build` + `eslint` clean when touched.
- **Design system is law.** `PulseColors`/`PulseFont`/`PulseRadius`/`PulseLayout`/`PulseCard`/`StatusChip` per
  `.cursor/rules/design-system.mdc`. SF Symbols only, no emoji in rendered UI, primary buttons black, hairline
  cards, calm whitespace. Travel + chat cards must look flagship-grade.
- **Honest UX.** Connector/booked/synced/saved state shown to the user must reflect reality. Unavailable things are
  clearly disabled/labeled, never faked.
- **Schema-driven, declarative cards.** Extend the strict `CoachResponse` schema (every property in `required`,
  `additionalProperties: false`); never render arbitrary HTML/eval'd code. Cards ride along in `CoachMessage.cardsJSON`.
- **Provider = OpenRouter.** Web backend uses `OPENROUTER_API_KEY`; no OpenAI keys/calls. iOS + OAuth secrets live in
  the Keychain. No secrets in source.
- **One shape, two surfaces.** Travel results render identically in chat and on the Travel screen; "save to trip"
  persists a real `TripItem`.
- **Interconnection via UUID FKs.** Cross-module links are additive, defaulted foreign-UUID fields (precedent:
  `Note.linkedTaskId`); no cross-module `@Relationship`s. Never force-pivot an unrelated chat to health.
- **Multi-source health.** New metric kinds/sources extend `MeasurementKind`/`MeasurementSource`/`webKind(for:)`
  additively and feed the existing `Measurement`/`ActivityDaily`/`SleepSession` stores so cloud sync just works.
  Health Connect is Android-only (deferred); iOS uses Fitbit + Google Fit REST over OAuth2.
- **Data integrity.** Additive, lightweight SwiftData migrations; cascade rules as established; never drop user data.
- **Accessibility & quality.** Dynamic Type, VoiceOver labels, 44pt tap targets; tests on each QA pass.
- **One iteration at a time.** A single shippable step, then stop — keeping the project reviewable.
```




