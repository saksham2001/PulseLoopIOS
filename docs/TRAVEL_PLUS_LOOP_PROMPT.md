# Travel+ — Comprehensive Travel Sub-App Open Loop Prompt

_Goal: turn the Travel module from "AI fills an empty list" into a comprehensive,
self-serve travel planner that's great even before/without the AI — while keeping
the AI chat output reliable. iOS is the primary surface._

Run this loop **iteration by iteration**. After each iteration: build, fix, keep
the suite green, append a dated entry to `docs/TRAVEL_PLUS_PROGRESS.md`, then move
on. Do not stop until every track below is `done`.

---

## NON-NEGOTIABLE: Follow the app design system

Every view, sheet, row, button, chip, and empty state you add or touch MUST follow
`.cursor/rules/design-system.mdc`. This is a hard acceptance criterion for every
iteration — a feature is NOT done if it violates the design system. Key rules:

- **No emoji anywhere in rendered UI.** Use `Image(systemName:)` SF Symbols only.
  (Chat travel-card kinds map to SF Symbols via `TripItemKind.icon` — keep it that way.)
- **Colors via `PulseColors.*`** tokens only (`.background`, `.canvas`, `.fillSubtle`,
  `.fillMuted`, `.borderHairline`, `.borderStrong`, `.textPrimary/.Secondary/.Muted/.Faint`,
  `.accent`). Accent is for rare emphasis only.
- **Primary buttons = `Color.black` fill, white text** (`PulseFont.bodySemibold(15)`,
  height 44, radius 12). Secondary = outlined with `borderStrong`. Never accent-filled buttons.
- **Typography via `PulseFont.*`**: headings `title(28)`/`titleMedium(22)` (serif),
  body `body(14–15)`, buttons `bodySemibold(15)`, section labels `bodyMedium(11)` UPPERCASED + `.tracking(0.8)` + `.textMuted`.
- **Cards**: 16–20px padding, 14–16px continuous corner radius, 1pt `borderHairline`
  border (never shadow-only). Prefer the existing `pulseCardSurface()` / `PulseCard`.
- **Spacing**: page padding 20, inter-card 14, section vertical 10–14.
- **Sheets**: `.presentationDetents`, `.presentationDragIndicator(.visible)`,
  `PulseColors.background` bg, left-aligned bold 22pt title.
- **Section headers**: uppercase, tracked, muted.
- `.buttonStyle(.plain)` inside `Button`/`NavigationLink` wrappers.

Reuse the existing Travel UI vocabulary already in `TravelView.swift`
(`pulseCardSurface()`, `StatusChip`, `TravelFormat`, `TripItemRow`, money formatting,
`TripItemKind.icon/label`). Match it; don't invent a parallel style.

---

## The problem (from the user)

1. **Chat output is unreliable**: asking the assistant to plan a trip sometimes
   returns plain text and adds nothing to the trip, leaving a dead-end empty trip.
2. **The Travel app isn't comprehensive**: an empty trip is a dead end; everything
   depends on the AI; there's no manual add/edit, no packing list / docs, no
   destination info, no in-trip discovery.

## Definition of done

A user can plan a trip end-to-end **with or without** the AI, the empty states are
actionable (never dead ends), the AI chat reliably produces tappable cards that save
into the trip, and the whole thing is on-design and green.

---

## Tracks

### T1 — Coach prefill plumbing (foundation)
- Add `var prefill: String?` to `CoachNavigation`. `CoachView` consumes it into its
  `draft` on appear/open and clears it (focus the composer). Do NOT auto-send.
- Add a small helper so any view can do "Ask AI: <prompt>" → set `prefill`, request
  the Ask-AI surface (the command palette / coach fullScreenCover), and dismiss to it.
- Acceptance: tapping an "Ask AI" affordance opens the coach with the prompt typed in.
- Tests: a unit test asserting `CoachNavigation.prefill` round-trips; build green.

### T2 — Actionable empty states (no dead ends)
- `TravelView` empty state: a primary **Plan a trip with AI** button (prefill a good
  planning prompt) + a secondary **New trip** (manual create sheet from T3).
- `TripDetailView` empty itinerary: replace the lone gray sentence with an actions
  card — **Plan this trip with AI** (prefill referencing the destination/dates),
  **Add item** (manual, T3), and a row of quick category chips (Flights/Stay/Things
  to do/Food/Transport) that open the AI or the manual add prefilled to that kind.
- Acceptance: no Travel screen is ever a dead end; all on-design.

### T3 — Manual create & edit (AI-independent)
- **New Trip sheet**: destination (required), origin, dates, travelers, budget(+currency),
  notes. Persists a `Trip`. Reachable from TravelView header + empty state.
- **Add/Edit Item sheet**: kind picker (SF Symbol per kind), title, details, location,
  url, price(+currency), day, booked toggle. Create new or edit an existing `TripItem`.
  Reachable from detail header (+), each section header (+), and tapping a row to edit.
- Use design-system sheets (detents, drag indicator). Validate required fields.
- Tests: creating a trip + adding/editing/deleting an item via the sheet's save path
  (extract logic to a testable function/VM if needed). Build green.

### T4 — Packing list & travel documents
- Packing list: checkable items grouped on the trip (reuse the linked-`TaskItem`
  pattern with a distinct group e.g. "Packing", or a lightweight model — pick the
  simplest that fits and note the decision). Add/check/remove inline.
- Travel docs: a section to capture confirmations / passport / visa references as
  `note`-kind items or linked notes (reuse `createTripNote` shape). Quick add.
- A coach tool to generate a smart packing list for a trip (weather/length/destination
  aware) writing into the same store. On-design UI.
- Tests: packing add/check; coach packing-list tool writes items. Build green.

### T5 — Destination info card
- A compact destination card on the trip: currency, language, rough time-zone offset
  from the user, plus a short "good to know" line. Keep it resilient/offline-friendly
  (don't hard-depend on a live network call; if you add a coach tool to fetch live
  weather/FX, degrade gracefully when unavailable).
- Prefer a coach `get_destination_info` read tool the model fills from web_search, that
  the UI can also render if present; otherwise a tasteful static/derived fallback.
- On-design (icon + label rows, muted section header). Tests where logic is testable.

### T6 — In-trip discovery entry points
- Each itinerary category section gets a subtle **Find with AI** affordance that
  prefills a category-specific prompt referencing the trip (e.g. "Find 3 highly-rated
  restaurants near my hotel in {destination} for {dates}; show as cards").
- A trip-level **Find more** that prefills a broad discovery prompt.
- These reuse T1 prefill plumbing. On-design (small accent/secondary affordances).

### T7 — Harden chat travel output
- Strengthen `CoachPromptBuilder` travel guidance: when planning, after web_search
  the model MUST call `prepare_travel_cards` and copy results verbatim; never dump a
  long plain-text option list; and when the user has an active trip, offer to save the
  shown options (or save the chosen ones with `add_trip_item`).
- Make the in-chat travel cards never a dead-end: ensure "Save to trip" is always
  available when cards render, and that saving targets the active trip (already wired —
  verify + test). Consider a "View trip" affordance after a save.
- Tests: existing `CoachTravelCardsTests` still pass; add coverage for any new behavior.

### T8 — Live internet routes & deals (real APIs)
The user wants Travel connected to the internet to find the best **routes and deals**
through APIs — not just static/guessed content. Build a real, networked travel-data
layer behind a testable seam, degrade gracefully offline, and surface results in both
the chat cards and the trip.

- **Networking seam**: reuse the existing `HTTPTransport` protocol (as the wearables
  layer does) so every provider is unit-testable with a stubbed transport. No raw
  `URLSession` calls scattered in views/tools.
- **Provider abstraction**: a `TravelSearchProvider` protocol with concrete methods
  for the core needs — `searchFlights`, `searchStays`, `searchActivities`/`places`,
  and (where available) `priceDeals`. Define typed result structs that map cleanly to
  `CoachTravelCard` / `TripItem` (title, price+currency, time, location, rating,
  booking url, lat/lon).
- **Real data sources** (pick reputable, documented APIs; keep keys in Info.plist /
  Keychain like the wearable client IDs, and treat them as configurable —
  `isConfigured` gating + graceful "not configured" fallback):
  - Flights/routes & fares: a flight-search/fare API (e.g. an Amadeus-style or
    equivalent routes+price endpoint). Surface best routes + price.
  - Stays: a lodging/hotels search API.
  - Things to do / restaurants / geocoding: a places/POI API (and reuse Apple
    `MKLocalSearch`/CoreLocation where it suffices to avoid extra keys).
  - "Deals": cheapest-fare / price-comparison style results where the API supports it.
- **Coach integration**: add read tools (e.g. `search_flights`, `search_stays`,
  `search_places`) that call the providers and return option lists the model turns
  into `prepare_travel_cards`. Prefer these structured tools over free-form web_search
  for bookable inventory, falling back to web_search when a provider is unconfigured.
- **In-app integration**: the in-trip "Find with AI" / discovery entry points (T6)
  and a manual "Search live" affordance use the same providers so results (with real
  prices/links) can be saved straight into the trip.
- **Resilience**: timeouts, `NetworkRetry`, and a clean degraded path when offline or a
  key is missing — never crash, never block the UI; show an honest empty/fallback state.
- **Config & docs**: document required API keys + how to set them; default placeholders
  must be rejected by `isConfigured` (mirror the wearables `REPLACE_*` pattern).
- Tests: each provider's request-building + response-parsing is unit-tested over a
  stubbed `HTTPTransport`; tool wiring tested; `isConfigured` gating tested. Build green.
- Design system still applies to any UI added here (no emoji; PulseColors/PulseFont;
  black primary buttons; hairline cards; design-system sheets).

### T9 — Best deals via credit card points / rewards
The user wants Travel to compute the **best deal accounting for credit card points and
rewards**, not just the lowest cash price. Add a points-aware valuation layer over the
T8 providers so an option's true cost reflects how the user pays.

- **User reward profile**: let the user record the cards/loyalty programs they hold
  (e.g. card name, rewards currency such as "Amex MR" / "Chase UR" / airline miles,
  current points balance, and per-category earn multipliers — travel/dining/other).
  Persist as a small SwiftData model. On-design entry/edit sheet (design-system).
- **Points valuation via API**: pull points/miles valuations and transfer-partner data
  from a rewards/points-valuation API (over the same testable `HTTPTransport` seam,
  with `isConfigured` gating + graceful fallback to sensible built-in cent-per-point
  defaults when no key is set). Support converting an award price (points + fees) and a
  cash price into a comparable **effective cost** using the user's valuations.
- **Best-deal engine**: for each flight/stay option from T8, compute:
  - cash cost, points-redemption cost (points × cpp + taxes/fees), and net **effective
    cost after expected earn** (points earned on the spend × cpp), then rank options by
    effective value. Show the recommended pay method per option.
- **Surfacing**: travel cards and the trip show the cash price AND a concise
  points/“best value” line (e.g. "≈ 35k pts + $56, ~$420 value — pay with Sapphire").
  A trip-level / coach summary recommends the optimal redemption across the trip.
- **Coach integration**: a tool the model can call (e.g. `value_with_points` /
  `best_redemption`) that takes options + the user's reward profile and returns the
  ranked best-value recommendation, fed into `prepare_travel_cards`.
- **Resilience & honesty**: when valuations/earn data are estimates, label them as
  estimates; degrade gracefully offline/unconfigured; never invent guaranteed prices.
- Tests: valuation math (cpp conversion, earn, effective cost, ranking) is pure and
  unit-tested; provider request/response parsing tested over a stubbed transport;
  `isConfigured` gating + default-cpp fallback tested. Build green.
- Design system applies to all reward-profile and points UI (no emoji; PulseColors/
  PulseFont; black primary buttons; hairline cards; design-system sheets).

---

## Acceptance for the whole loop
- [ ] iOS builds green; full test suite green each iteration.
- [ ] No emoji in any rendered Travel UI; all new UI uses `PulseColors`/`PulseFont`,
      black primary buttons, hairline cards, design-system sheets.
- [ ] A trip can be fully planned manually (no AI) and via AI; no dead-end screens.
- [ ] Chat travel planning reliably renders saveable cards; saving lands in the trip.
- [ ] Travel pulls **live routes & deals from real APIs** over a testable transport,
      surfaced in chat cards and the trip, with graceful offline/unconfigured fallback.
- [ ] Best deals factor in **credit card points/rewards**: options show an effective
      points-aware cost & recommended pay method, with estimates labeled honestly.
- [ ] App runs on the simulator with the new flows.
