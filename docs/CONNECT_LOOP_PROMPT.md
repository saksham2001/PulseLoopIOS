# Connect — Wearables & Accounts Integration Open Loop Prompt

_Goal: turn the **Connect** screen from a wall of "Unavailable" / "Not configured
in this build" / "Not yet available" placeholders into a real, working integrations
hub. A user can link their wearables (Oura, Whoop, Garmin) and accounts (Gmail,
Calendar, Slack, Notion/Todoist) over OAuth, their data flows into the same stores
the dashboard and assistant already read, and every connector reflects an **honest**
live status. iOS is the primary surface._

Run this loop **iteration by iteration**. After each iteration: build, fix, keep the
suite green, run it on the simulator, append a dated entry to
`docs/CONNECT_PROGRESS.md` (newest first), then move on. Do not stop until every
track below is `done`.

---

## NON-NEGOTIABLE: Follow the app design system

Every view, sheet, row, button, chip, pill, and empty state you add or touch MUST
follow `.cursor/rules/design-system.mdc`. A feature is NOT done if it violates it.

- **No emoji anywhere in rendered UI.** SF Symbols via `Image(systemName:)` only.
- **Colors via `PulseColors.*`** tokens only (`.background`, `.canvas`, `.fillSubtle`,
  `.fillMuted`, `.borderHairline`, `.borderStrong`, `.textPrimary/.Secondary/.Muted/.Faint`,
  `.success`, `.alert`, `.accent`). Accent for rare emphasis only.
- **Primary buttons = `Color.black` fill, white text** (`PulseFont.bodySemibold(15)`,
  height 44, radius 12). Secondary = outlined with `borderStrong`. Never accent-filled buttons.
- **Typography via `PulseFont.*`**: headings `title(28)`/`titleMedium(22)` (serif),
  body `body(12–15)`, buttons `bodySemibold(12–15)`, section labels
  `bodyMedium(11)` UPPERCASED + `.tracking(0.8)` + `.textMuted`.
- **Cards**: 12–20px padding, 14px continuous corner radius, 1pt `borderHairline`
  border (never shadow-only).
- **Sheets**: `.presentationDetents`, `.presentationDragIndicator(.visible)`,
  `PulseColors.background` bg, left-aligned bold title.

Reuse the existing Connect vocabulary already in `ConnectAccountsView.swift`
(`ConnectorRow`, `ConnectorStatusPill`, `connectorCard`, `sectionLabel`, `divider`)
and the status model in `ConnectorStatus.swift`. Match it; do not invent a parallel style.

---

## The problem (from the user)

On the **Connect** screen today:
- **Wearable accounts** (Fitbit, Google Fit) read "Not configured in this build" —
  the OAuth code exists but no client IDs ship, so they are inert.
- **More wearables** (Oura Ring, Whoop, Garmin) read "Not yet available" — pure
  placeholders with no backing integration.
- **Accounts** (Gmail, Google & Apple Calendar, Slack, Notion & Todoist) read "Not
  yet available" — pure placeholders.

The user wants the app to **actually connect with wearables and accounts**.

## What already exists (build on it — do NOT rebuild)

A clean, testable, on-design wearable integration pattern is already shipped:

- `WearableProvider` enum (`fitbit`, `googleFit`) with `displayName`,
  `iconSystemName`, `measurementSource`, `activitySource`
  (`PulseLoop/Services/Wearables/WearableTokenStore.swift`).
- `WearableConnectionManager` (`@MainActor @Observable`, `.shared`) owns
  connect/disconnect/sync and **persists into the same `ActivityDaily` (steps) +
  `Measurement` (HR/SpO₂) stores** Apple Health uses, so the dashboard and coach pick
  the data up automatically.
- `WearableDataSource` protocol + `FitbitDataSource` / `GoogleFitDataSource`
  (request building + response parsing over the injectable `HTTPTransport` seam).
- `WearableOAuthAuthenticator` + `PKCEChallenge` + `WearableTokenStore` (Keychain) +
  `WearableOAuthConfig.isConfigured(_:)` (rejects `YOUR_*` / `REPLACE*` placeholders).
- `ConnectorStatus` (`.forWearable`, `.forHealthKit`, `.forCloudSync`,
  `.unavailable(reason:)`) + `ConnectorRow` / `ConnectorStatusPill` render it honestly.
- `HTTPTransport` protocol (stub it in tests; never raw `URLSession` in views/tools).

**Pattern to mirror everywhere below:** OAuth/PKCE → Keychain token store →
`HTTPTransport`-based data source with request-build + response-parse split →
`isConfigured` gating with `REPLACE_*` placeholders in `Info.plist` → ingestion into a
shared store → honest `ConnectorStatus` row. Every new piece must be unit-testable
with a stubbed transport.

## Definition of done

Every connector on the Connect screen either (a) genuinely connects over OAuth and
syncs real data into the shared stores, or (b) shows an honest, accurate status. No
fake "Connect" buttons. Wearable data lands in `ActivityDaily`/`Measurement`; account
data lands in the right stores (events → calendar/`TaskItem`, messages/receipts →
inbox/`InboxItem`/notes). The assistant can read and act on connected data. All
on-design, all green, runs on the simulator.

---

## Tracks

### T1 — Light up the existing wearables (Fitbit + Google Fit)
- Make the already-built Fitbit + Google Fit connectors reachable: add their OAuth
  client IDs / redirect URIs to `Info.plist` as `REPLACE_*` placeholders (documented),
  wire the URL scheme for the redirect callback, and confirm `isConfigured` flips true
  when a real ID is present and false for placeholders.
- Verify end-to-end on the simulator with a real (or sandbox) client ID: connect →
  consent → initial sync → row shows "Connected" + last-sync; steps/HR/SpO₂ appear on
  the dashboard; "Sync now" / "Disconnect" work.
- Acceptance: with no IDs the rows honestly say "Not configured"; with IDs they
  connect and sync. Document the exact setup in `docs/CONNECT_PROGRESS.md`.
- Tests: extend the existing wearable OAuth/data-source tests (stubbed transport) for
  config gating + request/response parsing. Build + suite green.

### T2 — Generalize the provider model for new wearables
- Extend `WearableProvider` (or introduce a parallel `enum` if cleaner) to add
  `oura`, `whoop`, `garmin`, keeping `displayName`/`iconSystemName`/`measurementSource`/
  `activitySource` consistent. Move the Connect screen's hardcoded "More wearables"
  placeholder list onto real provider rows driven by `isConfigured`.
- `WearableConnectionManager.source(for:)` returns the right `WearableDataSource` per
  provider. Each new provider gets its own `*DataSource` + `*OAuthConfig` entry.
- Acceptance: the "More wearables" section is data-driven; unconfigured providers show
  "Not configured", not "Not yet available". On-design.
- Tests: provider metadata + `source(for:)` mapping covered. Build green.

### T3 — Oura, Whoop, Garmin data sources
- For each, add a `WearableDataSource` implementation over `HTTPTransport`:
  - **Oura** (OAuth2): daily activity (steps), sleep, readiness/HRV, SpO₂ where available.
  - **Whoop** (OAuth2): recovery, strain, HR, sleep.
  - **Garmin** (OAuth — note Garmin uses OAuth1.0a/Health API; if its flow doesn't fit
    the PKCE authenticator, add a minimal Garmin-specific authenticator behind the same
    `WearableDataSource` interface, or honestly mark it "Not configured" with a clear
    reason until backend support exists). Map steps/HR/sleep.
- Persist via the existing `upsertSteps` + `Measurement` paths (and extend the shared
  stores only if a new metric like readiness/recovery needs a home — pick the simplest
  fit and note the decision). Sleep should flow into the existing sleep store.
- Resilience: timeouts, `NetworkRetry`, graceful degrade when offline/unconfigured;
  never crash; surface `lastError` into the row.
- Tests: each source's request-building + response-parsing over a stubbed transport;
  token-refresh path; config gating. Build + simulator green.

### T4 — Accounts foundation (OAuth account layer)
The accounts (Gmail/Calendar/Slack/Notion/Todoist) have **no** backing today. Build a
parallel, testable account-connection layer mirroring the wearable one — do not
overload the wearable types with non-health concerns.

- `AccountProvider` enum (`gmail`, `googleCalendar`, `appleCalendar`, `slack`,
  `notion`, `todoist`) with `displayName`/`iconSystemName`/scopes.
- `AccountConnectionManager` (`@MainActor @Observable`, `.shared`) owning
  connect/disconnect/sync, mirroring `WearableConnectionManager`.
- `AccountDataSource` protocol + per-provider implementations over `HTTPTransport`.
- Reuse `PKCEChallenge` + a Keychain token store (generalize `WearableTokenStore` or
  add an `AccountTokenStore`), `isConfigured` gating with `REPLACE_*` Info.plist keys,
  and `ConnectorStatus.forAccount(...)` (add this case mirroring `.forWearable`).
- **Apple Calendar** is local (EventKit), not OAuth — gate it on `EKEventStore`
  authorization, not a client ID, and surface its own honest status.
- Acceptance: the "Accounts" section is data-driven; rows reflect real OAuth/EventKit
  state; no fake buttons. Privacy note stays accurate ("never posts on your behalf").
- Tests: account provider metadata, manager lifecycle, config/auth gating. Build green.

### T5 — Calendar + Gmail ingestion (read-first, write-guarded)
- **Calendar** (Google Calendar over OAuth + Apple Calendar via EventKit): read
  upcoming events into the app's day/week planning surfaces (map to the existing
  calendar/`TaskItem`/event model — reuse, don't duplicate). Two-way create/update is
  optional and, if added, MUST go through the existing **PendingAction confirmation**
  path (the assistant proposes; the user confirms) — never write silently.
- **Gmail** (read-only scope first): pull receipts/bills/invites; route them into the
  existing AI capture/inbox path (`InboxItem`) so the assistant can file them as a
  task/event/note. Never send mail.
- Resilience + honesty: read-only by default; any write requires explicit consent and
  is labeled. Degrade gracefully offline/unconfigured.
- Tests: parsers for events + messages over stubbed transport; mapping into the shared
  stores; the write-confirmation gating. Build + simulator green.

### T6 — Slack + Notion/Todoist
- **Slack** (OAuth): read mentions/DMs the user authorizes into the inbox capture
  path; no posting unless explicitly confirmed via PendingAction.
- **Notion / Todoist** (OAuth): two-way task sync with the app's `TaskItem` store —
  pull tasks in; pushing changes out is confirmation-gated. Pick one direction to fully
  finish first (pull-in), then add guarded push.
- Each is its own `AccountDataSource`, `isConfigured`-gated, stubbed-transport tested.
- Tests: task/message parsing + sync mapping; gating. Build green.

### T7 — Assistant + dashboard awareness
- Ensure connected data is **automatically** visible: wearable metrics already flow
  into `ActivityDaily`/`Measurement`; confirm the coach context packet surfaces newly
  connected sources, and that calendar/inbox items reach the relevant surfaces.
- Add read tools so the assistant can use the new data (e.g. `list_upcoming_events`,
  `list_recent_messages`) and keep all mutations behind PendingAction confirmation.
- A small "what's connected" line the coach can reference (which sources are live).
- Tests: context packet includes connected-source signal; tool wiring. Build green.

### T8 — Background refresh & token hygiene
- Periodic/background sync for connected providers (respecting iOS background limits;
  reuse any existing sync coordinator pattern). Token auto-refresh on 401 with a single
  retry, then surface a clear "reconnect" state in the row on hard failure.
- Make sure disconnect fully clears Keychain tokens + cached state for every provider.
- Tests: refresh-on-401 retry, disconnect clears state, last-sync persistence. Build green.

---

## Cross-cutting requirements (apply to every track)

- **Testable seam**: all network calls go through `HTTPTransport`; every provider's
  request-building and response-parsing is unit-tested with a stubbed transport. No raw
  `URLSession` in views or tools.
- **Honest status**: never show a "Connect" affordance that does nothing. Unconfigured
  → "Not configured" with a real reason; configured-but-not-connected → actionable;
  connected → status + last-sync + Sync/Disconnect. Drive everything through
  `ConnectorStatus`.
- **Config & secrets**: client IDs/secrets live in `Info.plist` (or Keychain for
  secrets) as `REPLACE_*` placeholders rejected by `isConfigured`; never commit real
  secrets. Document required keys + setup in `docs/CONNECT_PROGRESS.md`.
- **Privacy**: read-only by default; any write/post is explicit, confirmation-gated
  (PendingAction), and the on-screen privacy note stays true ("reads only what you
  authorize and never posts on your behalf"). On-device processing where feasible.
- **Resilience**: timeouts, `NetworkRetry`, graceful offline/unconfigured degrade,
  surfaced `lastError`; never crash, never block the UI.
- **Design system**: every added row/sheet/button is on-design (no emoji;
  `PulseColors`/`PulseFont`; black primary buttons; hairline cards; design-system sheets).

---

## Acceptance for the whole loop
- [ ] iOS builds green; full test suite green each iteration; app runs on the simulator.
- [ ] Fitbit + Google Fit connect over OAuth and sync into the dashboard when IDs are set.
- [ ] Oura, Whoop, Garmin each connect + sync (or show an honest, documented reason if a
      flow can't ship), with data in the shared stores.
- [ ] Gmail, Calendar (Google + Apple/EventKit), Slack, and Notion/Todoist connect over
      OAuth/EventKit and ingest into the right surfaces; writes are confirmation-gated.
- [ ] No fake "Connect" buttons anywhere; every connector reflects honest live status.
- [ ] All network providers are testable over a stubbed `HTTPTransport`; secrets are
      `REPLACE_*`-gated and documented; no secrets committed.
- [ ] The assistant can read connected data via read tools and only mutates via
      PendingAction confirmation.
- [ ] No emoji in any rendered Connect UI; all new UI uses `PulseColors`/`PulseFont`,
      black primary buttons, hairline cards, design-system sheets.
