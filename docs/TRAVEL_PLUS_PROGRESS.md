# Travel+ Progress

_Tracker for `docs/TRAVEL_PLUS_LOOP_PROMPT.md`. Append a dated entry per iteration.
Every iteration must follow `.cursor/rules/design-system.mdc` (no emoji in UI,
PulseColors/PulseFont, black primary buttons, hairline cards, design-system sheets)._

## Status
| Track | Title | Status |
|-------|-------|--------|
| T1 | Coach prefill plumbing | done |
| T2 | Actionable empty states | done |
| T3 | Manual create & edit | done |
| T4 | Packing list & travel docs | done |
| T5 | Destination info card | done |
| T6 | In-trip discovery entry points | done |
| T7 | Harden chat travel output | done |
| T8 | Live internet routes & deals (real APIs) | done |
| T9 | Best deals via credit card points / rewards | done |

## Decision log
- (none yet)

## Iteration history
_(append a dated entry per completed iteration)_
- **2026-06-24 — T1 done.** Coach prefill plumbing: `CoachNavigation.prefill` + `askAI(_:)` (sets prefill, posts `.openCoach`), new `.openCoach` notification consumed by `MainTabView` to present the coach, and `CoachView` drops the prefill into its composer on appear (focus, no auto-send). Tests `TravelPlusTests` (2/2). Build green.
- **2026-06-24 — T2, T3, T6 done.** Actionable empty states (TravelView empty: Plan with AI + New trip; TripDetail empty: Plan with AI + Add manually + quick-add category chips). Manual create/edit via `TripEditSheet` + `TripItemEditSheet` (testable `TravelEditing`), reachable from list "+", detail menu, per-section "+", and tap-to-edit rows. Per-section "Find with AI" + trip-level discovery prefills (T6). Build green; `TravelPlusTests` create/edit/rollup tests pass.
- **2026-06-24 — T4 done.** Packing list (group "Packing" `TaskItem`s) with inline add/check/remove + `create_packing_list` coach tool; Travel documents section (passport/visa/confirmation `Note`s) with `TravelDocSheet`. Notes section now excludes docs. Build green; packing tool test passes.
- **2026-06-24 — T5 done.** Destination info card (currency/language/time-zone delta/tip) backed by additive `Trip` fields + `set_destination_info` coach tool (validates IANA zone, fed from web_search) and a "Get with AI" affordance; synced to web payload. Build green; tz-delta + tool tests pass (27/27 travel tests).
- **2026-06-24 — T8 done.** Live travel-data layer behind a testable `HTTPTransport` seam: `TravelSearchProvider` protocol + normalized `TravelSearchResult` (maps 1:1 to `CoachTravelCard`/tool dict). `AmadeusFlightProvider` (OAuth2 client-credentials token cached in an actor, flight-offers search, ISO-duration formatting) for real fares; `AppleMapsPlaceProvider` (keyless `MKLocalSearch`) for stays/activities/restaurants/transport; `LiveTravelSearch` facade. New `search_flights` / `search_places` coach tools degrade gracefully (configured=false / noResults → web_search fallback). Keys read from Info.plist (`AMADEUS_CLIENT_ID/SECRET`, placeholder-gated). Prompt updated to prefer live tools. Build green; `TravelSearchTests` 16/16 + `TravelToolsTests` 12/12 pass.
- **2026-06-24 — T9 done.** Best deal accounting for points: `RewardCard` SwiftData model (currency, balance, cents-per-point, per-category earn) + design-system `RewardCardEditSheet` and `RewardWalletView` (reachable from Travel's "+" menu → Wallet & rewards). Pure `PointsValuator` engine (cpp conversion, expected-earn value, effective cash vs award cost, ranking) is unit-tested. `LivePointsValuationProvider` over the testable `HTTPTransport` with `isConfigured` gating + built-in `DefaultPointValues` cpp fallback (never breaks planning). Coach tools `list_reward_cards` / `add_reward_card` / `value_with_points` feed ranked, points-aware recommendations into `prepare_travel_cards`; values labeled as estimates. Prompt updated. Build green; full suite 379 tests, 0 failures (`RewardValuationTests` 15/15).
