# AI-Native Modular App — Progress Tracker

Companion to `docs/AI_NATIVE_LOOP_PROMPT.md`. Work top-to-bottom; bugs first.

## Backlog

### Bugs (silent failure / data loss)
- [x] **BUG-1** Persist + render ALL pending confirmations per turn (not just `.first`). `CoachViewModel`, `CoachActionCardView`.
- [x] **BUG-2** Surface `errorBanner` / transport failures visibly in `CoachView` (dismissible).
- [x] **BUG-3** Route destructive Travel ops (`delete_trip_item`, `update_trip` cancel) through `PendingAction` confirm cards.

### AI-native gaps
- [x] **AIN-1** Token streaming for assistant replies.
- [x] **AIN-2** Render persisted `CoachToolCall` trace as collapsible "what I did" under finished replies.
- [x] **AIN-3** Travel deep-link: `navigate_to` supports `tripDetail` + `trip_id` after `create_trip`.
- [x] **AIN-4** Day-by-day itinerary timeline + MapKit overview in `TripDetailView`.
- [x] **AIN-5** Single coherent suggestion row; action-capability chips, not just read-only questions.
- [x] **AIN-6** Stop/cancel button for in-flight turns.
- [x] **AIN-7** Header reflects the real provider/model actually used.
- [x] **AIN-8** Context-aware greeting (time-of-day + recent activity).

## Verification log
- Baseline: iOS `BUILD SUCCEEDED`, web `lint` + `build` clean (2026-06-24).
- BUG-1: pending actions stored as JSON array; all cards render; confirm/cancel per-index. iOS BUILD SUCCEEDED.
- BUG-2: orchestrator returns `errorMessage`; VM publishes to `errorBanner`; dismissible danger banner above composer. iOS BUILD SUCCEEDED.
- BUG-3: `delete_trip_item` + `update_trip(cancelled)` queue `deleteEntity` confirm cards; executor handles `trip`/`trip_item`. iOS BUILD SUCCEEDED.
- AIN-1: `TypewriterText` progressively reveals the latest reply's summary (gated to fresh messages); trace strip already streams live steps. iOS BUILD SUCCEEDED.
- AIN-2: `CoachToolTraceView` (`@Query` on `CoachToolCall`) shows a collapsible "N steps" under each assistant reply. iOS BUILD SUCCEEDED.
- AIN-3: `navigate_to` accepts `destination='trip'` + `trip_id` → `.tripDetail(uuid)`. iOS BUILD SUCCEEDED.
- AIN-4: `TripDetailView` adds By day/By type segmented itinerary + `TripMapView` (CLGeocoder pins). Shared formatters fix per-row allocation. iOS BUILD SUCCEEDED.
- AIN-5: cold-start chip row only on empty conversation (no double rows); added action-first Travel chips. iOS BUILD SUCCEEDED.
- AIN-6: `CoachViewModel.startTurn/cancel` tracks a cancellable task; composer shows a Stop button while sending; cancelled turns persist "Stopped." not an error. iOS BUILD SUCCEEDED.
- AIN-7: header subtitle mirrors `makeClient` resolution (Cloud AI / Bedrock / model name / Set up AI). iOS BUILD SUCCEEDED.
- AIN-8: greeting prefixed with time-of-day (`Good morning/afternoon/evening`). iOS BUILD SUCCEEDED.
- Tests: TravelToolsTests updated for the confirm-card archive flow; TravelTools/ModuleAwareChat/BrainTools suites pass. Pre-existing unrelated failures remain in SleepServiceTests (date-relative) and SubAppPlatformTests (credit ledger) — untouched by this work.
