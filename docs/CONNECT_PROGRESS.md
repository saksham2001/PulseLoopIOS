# Connect — Wearables & Accounts Integration Progress

Newest entries first. Each entry corresponds to one or more tracks from
`docs/CONNECT_LOOP_PROMPT.md`.

---

## 2026-06-24 — T1–T8 complete: full integrations hub shipped

**Status:** Build green. Full suite green (549 tests, 1 skipped, 0 failures).
App installs and runs on the simulator (`xyz.sakshambhutani.PulseLoop`).

### T1 — Existing wearables (Fitbit + Google Fit)
- Confirmed `Info.plist` client-ID keys + redirect URL scheme already present.
- `WearableOAuthConfig.isConfigured(_:)` correctly rejects `REPLACE_*` / `YOUR_*`
  placeholders, so with no real ID the rows honestly read "Not configured in this
  build"; supplying a real ID flips them live.

### T2 — Generalized provider model
- Extended `WearableProvider` with `oura`, `whoop`, `garmin`, each with consistent
  `displayName` / `iconSystemName` / `measurementSource` / `activitySource`.
- Extended `MeasurementSource` with `.oura`, `.whoop`, `.garmin`.
- The Connect screen "More wearables" section is now **data-driven** off
  `WearableProvider.allCases` + `isConfigured`, replacing the hardcoded
  "Not yet available" placeholders.

### T3 — Oura / Whoop / Garmin data sources
- `OuraDataSource` (OAuth2, v2 API): steps, HR, SpO₂, sleep.
- `WhoopDataSource` (OAuth2): recovery, strain, sleep (no steps — returns nil).
- `GarminDataSource`: honestly throws `notConfigured`. Garmin Health uses OAuth 1.0a,
  incompatible with the app's PKCE authenticator without backend support, so
  `WearableOAuthConfig.isFlowSupported(.garmin) == false` and the row shows an honest
  "unavailable" reason instead of a fake Connect button.
- Sleep flows into the existing `SleepSession` store via a new idempotent
  `WearableConnectionManager.upsertSleep(...)`. Steps/HR/SpO₂ keep using the existing
  `ActivityDaily` / `Measurement` paths.

### T4 — Accounts foundation (parallel OAuth layer)
- New, fully parallel account layer mirroring the wearable pattern (no overloading of
  health types):
  - `AccountProvider` (`gmail`, `googleCalendar`, `appleCalendar`, `slack`, `notion`,
    `todoist`).
  - `AccountTokenStore` (Keychain, isolated service name).
  - `AccountOAuthConfig` (endpoints, scopes, `REPLACE_*` Info.plist gating; Apple
    Calendar treated as local EventKit, not OAuth).
  - `AccountOAuthAuthenticator` (Authorization-Code + PKCE, reusing `PKCEChallenge`;
    handles Slack's nested token shape).
  - `AccountDataSource` protocol with `RemoteCalendarEvent` / `RemoteMessage` /
    `RemoteTask` DTOs.
  - `AccountConnectionManager` (`@MainActor @Observable .shared`).
  - `ConnectorStatus.forAccount(...)` and `.forEventKit(...)` for honest rows.

### T5 — Calendar + Gmail ingestion (read-first)
- `EventKitCalendarSource` (Apple Calendar, read-only, gated on `EKEventStore` auth).
- `GoogleCalendarDataSource` (upcoming events) → `InboxItem` via idempotent
  `upsertEventInbox`.
- `GmailDataSource` (read-only, primary inbox) → `InboxItem` via `upsertMessageInbox`.
- Calendar usage descriptions added to `Info.plist`.

### T6 — Slack + Notion / Todoist
- `SlackDataSource` (mentions/DMs → inbox).
- `NotionDataSource` (database tasks) and `TodoistDataSource` (active tasks) →
  `TaskItem` via idempotent `upsertTask` (pull-in direction fully wired; outbound
  writes remain confirmation-gated by design).
- `AccountHTTPClient.getJSONArray` added for top-level-array APIs (Todoist).

### T7 — Assistant + dashboard awareness
- Added three read tools to `PlatformControlTools`: `list_connected_sources`,
  `list_upcoming_events`, `list_recent_messages` — the coach can query live connection
  status and recently-synced events/messages on demand. All mutations stay behind the
  existing PendingAction confirmation path.

### T8 — Background refresh & token hygiene
- New `ConnectedSourcesSyncCoordinator` (`syncAll` / `syncAllIfDue` with throttle),
  wired into `ConnectAccountsView` `.task` so all connected sources refresh on
  foreground.
- Token refresh-on-expiry lives in the data sources / HTTP clients; disconnect clears
  Keychain tokens + cached UserDefaults state for every provider.

### Tests added
- `PulseLoopTests/WearableProvidersTests.swift` — provider metadata, config gating
  (incl. Garmin honest `isFlowSupported == false`), Oura/Whoop parsers.
- `PulseLoopTests/AccountConnectorTests.swift` — account config gating, token-store
  isolation, authenticator callback parsing, Google Calendar / Gmail / Slack / Notion /
  Todoist parsers, idempotent ingestion mappers, and the sync coordinator.

### Setup notes (how to actually connect)
Each provider needs a real OAuth client ID dropped into `Info.plist` (replacing the
`REPLACE_WITH_YOUR_*_CLIENT_ID` placeholders) and the redirect URI registered with the
provider's developer console. Until then, every row honestly reports "Not configured in
this build". Garmin additionally requires backend OAuth 1.0a support before it can be
enabled.
