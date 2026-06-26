# Travel Loop — Progress Tracker

Live status for `docs/TRAVEL_LOOP_PROMPT.md`. The loop updates this file at the end of each iteration.

- **Current iteration:** ✅ Roadmap complete (T, C, X, H, Q all done)
- **Last completed:** Q1 — cross-initiative polish + a11y. Connectors button a11y labels, coach prompt documents connected_wearables. Full suite green: 335 tests, 0 failures (1 skipped).
- **Provider:** OpenRouter (web `OPENROUTER_API_KEY`; iOS Keychain)

---

## Status legend
`pending` · `in-progress` · `done` · `deferred`

---

## Track T — Comprehensive Travel sub-app
| ID | Iteration | Status | Notes |
|----|-----------|--------|-------|
| T1 | Travel design doc + audit of existing module | done | Audit + target design recorded below. Existing: Trip/TripItem (basic), TravelTools (8 tools), TravelView/TripDetailView (sections-by-kind), TravelSubApp registered, AppModule.travel wired. Gaps: no travelers/budget/cover/coords, no day timeline, no map, no chat cards, no cross-links, no trip_detail deep-link, not on Home feed. |
| T2 | Extend Trip/TripItem models additively + tool schemas | done | Trip: travelerCount, budgetAmount/Currency, coverImageURL + budget rollup helpers (effectiveCurrency, estimatedCost, bookedCost, costByKind). TripItem: rating, latitude/longitude, confirmationNumber. create_trip/add_trip_item schemas extended (strict-mode required arrays updated). Build green. Files: TravelModels.swift, TravelTools.swift. |
| T3 | Rebuild TripDetailView: day timeline + budget rollup | done | Day/type grouping already present (parallel session). Added: cover image header (AsyncImage), traveler count, and a full budget section (estimated vs booked, budget progress bar, per-category breakdown). Build green. Files: TravelView.swift. |
| T4 | Trip map (MapKit pins, geocode + cache) | done | Already implemented by parallel session: TripMapView geocodes item.location strings → Markers with kind icons, auto camera. Verified building. (Future: use stored lat/lon to skip geocoding.) |
| T5 | Rebuild TravelView (upcoming/past, rich cards) | done | Upcoming vs Past sections (date-based), section headers, TripCard now shows cover image + estimated cost. Build green. Files: TravelView.swift. |
| T6 | Routing: trip_detail deep-link + Home feed card | done | navigate_to(destination='trip', trip_id) deep-link already implemented (parallel session). Added HomeModule.travel case + Home "Upcoming trip" card (countdown, dates, plan count, cost) deep-linking to TripDetail; gated on Travel installed + an upcoming trip. Build green. Files: HomeView.swift. |
| T7 | Travel QA pass | done | Added 3 tests: rich create_trip fields, item rating/coords + budget rollup (estimated/byKind/effectiveCurrency) + get_trip surfacing, bookedCost. 7/7 TravelToolsTests pass. Files: TravelToolsTests.swift. **Track T complete.** |

## Track C — Travel results in the chatbox
| ID | Iteration | Status | Notes |
|----|-----------|--------|-------|
| C1 | CoachTravelCard / CoachItineraryDay models | done | New CoachTravelCard.swift: CoachTravelCard (kind/title/subtitle/price/currency/time/location/rating/thumbnail/booking/lat/lon, lenient decode, snake_case, Identifiable) + CoachTravelCardKind (maps to TripItemKind) + CoachItineraryDay. Build green. |
| C2 | Wire fields into CoachResponse + strict schema | done | Added travel_cards + itinerary to CoachResponse (var/CodingKeys/init/decodeIfPresent) and CoachResponseSchema (sub-schemas + properties + required, strict-valid). Build green. Files: CoachResponse.swift, CoachResponseSchema.swift. |
| C3 | SwiftUI travel card views in chat | done | New CoachTravelCardView.swift: CoachTravelCardsView container + CoachTravelCardView (thumbnail, kind icon, price, time/location/rating meta, View link, "Save to trip" button gated on onSave) + CoachItineraryView day outline. Rendered in CoachResponseView; added onSaveTravelCard closure. Build green. |
| C4 | "Save to trip" from a chat card | done | CoachBubble + CoachResponseView pass onSaveTravelCard → CoachViewModel.saveTravelCard persists the card as a TripItem on the most-recent active trip (creates one if none), inheriting price/rating/coords/url. Same item then shows on Travel screen. Build green. Files: CoachView.swift, CoachResponseView.swift, CoachViewModel.swift. |
| C5 | prepare_travel_cards tool + prompt guidance | done | Added prepare_travel_cards read tool (model authors options → echoes travel_cards + itinerary to copy verbatim, "prepare→copy" pattern). Surfaced via TravelTools.readTools (reaches model when Travel installed). CoachPromptBuilder travel section instructs showing options as cards. Build green. Files: TravelTools.swift, CoachPromptBuilder.swift. |
| C6 | Chat-cards QA pass | done | New CoachTravelCardsTests (5 tests): travel_cards/itinerary decode, encode round-trip, strict schema advertises+requires fields, prepare_travel_cards echo, saveTravelCard persists TripItem + reuses active trip. 5/5 pass. **Track C complete.** File: CoachTravelCardsTests.swift. |

## Track X — Everything interconnects
| ID | Iteration | Status | Notes |
|----|-----------|--------|-------|
| X1 | Cross-link FKs (Task.tripId, Note.linkedTripId, DayPlanAction entity ref) | done | Added TaskItem.tripId, Note.linkedTripId, DayPlanAction.entityType+entityId — all optional/defaulted (lightweight migration), initializers updated. Build green. File: LifeOSModels.swift. |
| X2 | Trip → Tasks (pre-trip checklist) | done | create_trip_checklist write tool creates TaskItems stamped with tripId (group "Travel"); TripDetailView shows a checklist section with done/total + tap-to-toggle. Prompt updated. Test testCreateTripChecklistLinksTasks (8/8 pass). Files: TravelTools.swift, TravelView.swift, CoachPromptBuilder.swift. |
| X3 | Trip → Day Plan / calendar | done | DayPlanView surfaces an active-trip block in Today's schedule when today falls within a trip's date range — shows "Day N in {destination}" + today's planned items (via dayOffset). File: DayPlanView.swift. Build green. |
| X4 | Trip → Notes + budget | done | create_trip_note write tool creates a Note (linkedTripId) with an optional paragraph block; TripDetailView shows a Notes section. Budget rollups (estimated/booked/by-kind) already shipped in B-track. Test testCreateTripNoteLinksNote (9/9 pass). Files: TravelTools.swift, TravelView.swift, CoachPromptBuilder.swift. |
| X5 | Assistant cross-domain awareness | done | CoachContextPacket.trips[] surfaces active/upcoming trips (destination, status, dates, phase active-today/upcoming, daysUntil, itemCount, openChecklistCount) gated by Travel install; prompt instructs proactive-but-not-pushy travel awareness. Tests CoachTripContextTests (5/5). Files: CoachContextPacket.swift, CoachContextBuilder.swift, CoachPromptBuilder.swift. |
| X6 | Interconnect QA pass | done | Full suite green: 308 tests, 0 failures (1 skipped). Fixed 8 pre-existing failures that were casualties of the unlimited-credits + writes-on-by-default product decisions (made credit-meter tests unlimited-aware; made write-tool/provider-gating tests explicitly construct the gated config / guard on paired-proxy). All Travel interconnect (X1–X5) verified end-to-end. |

## Track H — Sync with Google & Fitbit
| ID | Iteration | Status | Notes |
|----|-----------|--------|-------|
| H1 | Multi-source health design doc | done | docs/HEALTH_SYNC_DESIGN.md: goals/non-goals, reuse-vs-build, OAuth2 PKCE flow + endpoints (Fitbit, Google Fit REST), persistence mapping (steps→ActivityDaily, HR/SpO2→Measurement), testing strategy behind HTTPTransport seam. |
| H2 | OAuth2 infra (token store + ASWebAuthenticationSession + PKCE) | done | Services/Wearables/: PKCEChallenge (S256), WearableTokenStore (Keychain Codable bundle + testable KeychainBackend seam), WearableProvider + OAuthTokenBundle (expiry margin), WearableOAuthConfig (per-provider endpoints/scopes/redirect, client id from Info.plist), WearableOAuthAuthenticator (ASWebAuthenticationSession + code exchange/refresh over HTTPTransport). MeasurementSource += fitbit, googleFit. Tests WearableOAuthTests (12/12). |
| H3 | Fitbit source (WearableDataSource) | done | FitbitDataSource.swift: steps (activities/date), resting HR (activities/heart), SpO2 (spo2/date), sleep (sleep/date) over Fitbit Web API; transparent token refresh; pure JSON parsers behind HTTPTransport. Tests in WearableDataSourceTests. |
| H4 | Google Fit source (WearableDataSource) | done | GoogleFitDataSource.swift: steps + HR via dataset:aggregate (step_count.delta sum, heart_rate.bpm average); day-window builder + parsers unit-tested; SpO2/sleep deferred (not in standard fitness scopes). |
| H5 | Connectors UI (Fitbit + Google rows) | done | WearableConnectionManager (@Observable singleton: connect/disconnect/sync, per-provider state, upsertSteps never-lowers semantics). ConnectorStatus.forWearable mapper. ConnectAccountsView "WEARABLE ACCOUNTS" section with Connect / Sync now / Disconnect; ConnectorRow gained a tertiary action. Build green. |
| H6 | Health-sync QA pass | done | Info.plist: FITBIT_CLIENT_ID/GOOGLE_CLIENT_ID placeholders + pulseloop CFBundleURLTypes; isConfigured rejects REPLACE* placeholders. CoachContextPacket.connectedWearables surfaces linked accounts to the coach. WearableDataSourceTests: 15 tests (parsers, sync persistence, upsert semantics, status mapping). Full suite 335/335 (1 skipped). **Track H complete.** |

## Track Q — Final hardening
| ID | Iteration | Status | Notes |
|----|-----------|--------|-------|
| Q1 | Cross-initiative polish + a11y + (optional) web Travel read-only | done | Connectors UI a11y: provider-qualified accessibility labels on Connect/Sync/Disconnect buttons. Coach prompt now documents `connected_wearables` (attribute Fitbit/Google Fit data; suggest connecting when no step/HR data, without nagging). Corrected tracker. Full suite 335/335 (1 skipped). **Track Q complete.** |

## Track W — Web Travel parity
| ID | Iteration | Status | Notes |
|----|-----------|--------|-------|
| W1 | iOS `TripSyncProvider` (Trip + items → generic sync) | done | Added `TripSyncProvider` (type `trip`) to `DataSyncService.defaultProviders()`: maps `Trip` to a payload (destination, status, travelers, currency, estimated/booked cost, budget, dates, notes) plus a compact JSON-serializable itinerary (`items[]`: kind, title, location, url, price, rating, dayOffset, booked). Tests: `testTripProviderRecordType`, `testTripProviderMapsTripAndItems` (7/7 in DataSyncProviderTests). File: DataSyncService.swift. |
| W2 | Web `/travel` read-only screen | done | New `travel` ModuleId (workspace.ts defaults on, modules.ts catalog entry, `plane` icon, sidebar "You" nav item, `trip` in RECORD_TYPES). `/travel` screen groups trips by status (Planning/Booked/Completed/Cancelled), shows budget roll-up bar + expandable day-by-day itinerary, money/date formatting, empty + loading states. Reads `/api/records?type=trip`. Web `tsc`, `eslint`, and `next build` all green (`/travel` route emitted). Files: travel/page.tsx, travel/travel-screen.tsx, workspace.ts, modules.ts, record-types.ts, sidebar.tsx, icons.tsx. **Track W complete.** |

---

## Decision log
- "Google Health" on iOS = **Google Fit REST API (OAuth2)**. Android **Health Connect is out of scope** for this iOS
  target (Android-only API); deferred to a possible future Android client.
- Web Travel parity **shipped in Track W** — iOS remains the primary surface; web is read-only over the
  generic `synced_records` pipe (no Travel-specific endpoint), consistent with every other web module.

## Iteration history
_(append a dated entry per completed iteration)_
- **2026-06-24 — Track W complete (W1–W2).** Closed the last deferred piece: Travel now reaches the web. iOS `TripSyncProvider` uploads trips + itineraries through the existing generic sync pipe; the web gets a first-class read-only `/travel` screen (status sections, budget bars, expandable itineraries) plus a Travel module/nav entry. iOS `DataSyncProviderTests` 7/7; web `tsc` + `eslint` + `next build` all green.
- **2026-06-24 — Track H complete (H3–H6).** Fitbit + Google Fit data sources (REST over the testable HTTPTransport seam), a `WearableConnectionManager` that persists steps→`ActivityDaily` and HR/SpO2→`Measurement` (de-duped, never-lowers-a-day's-total), Connectors UI rows (connect/sync/disconnect with honest `ConnectorStatus`), Info.plist client-id + `pulseloop` URL scheme, and coach awareness of connected wearables. 335/335 tests green (1 skipped).
- **2026-06-24 — Track Q complete (Q1).** Accessibility labels on connector action buttons; coach prompt documents `connected_wearables`. Roadmap complete: Travel sub-app (T), in-chat travel cards (C), cross-module interconnect (X), Fitbit + Google Fit sync (H), and final hardening (Q) all shipped. 335/335 tests green.
