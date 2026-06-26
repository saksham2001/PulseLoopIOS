# Health Sync Design — Fitbit & Google Fit (Track H)

Adds two third-party health data sources to PulseLoop iOS: **Fitbit** and **Google Fit**
(Google's "health" on iOS = the **Google Fit REST API** over OAuth2; Android Health Connect is
out of scope on this iOS target). Both pull samples *in* and persist them so the existing
dashboard + coach pick them up for free.

## Goals
- Connect/disconnect Fitbit and Google Fit from the Connect screen.
- OAuth2 (Authorization Code + PKCE) via `ASWebAuthenticationSession`, tokens in Keychain.
- Pull steps + heart rate (and where available SpO2 / sleep) into `ActivityDaily` + `Measurement`
  tagged with the right `MeasurementSource`, so `MetricsService.buildTodaySummary` surfaces them
  with no consumer changes.
- Honest connector status (connected / last synced / error / needs-config).

## Non-goals (deferred)
- Background polling (`BGTaskScheduler`) — manual + on-open sync first; BG is a Q-track stretch.
- Writing data back to Fitbit/Google.
- Android Health Connect.

## Architecture (reuse vs build)
- **Reuse:** the `WearableDataSource` protocol (`Services/HealthKitIngestion.swift`) as the read
  abstraction; the `APIKeyStore`/Keychain upsert pattern (`Coach/Config/OpenAIKeychainStore.swift`)
  for tokens; `ConnectorStatus` + `ConnectAccountsView` rows for UI; persist into `Measurement`
  (HR/SpO2) and `ActivityDaily` (steps) like `HealthKitIngestion.importNow()`.
- **Build new:**
  - `OAuth2/` — a small PKCE + `ASWebAuthenticationSession` helper (`OAuth2Authenticator`) and a
    `OAuthTokenStore` (Keychain, stores a Codable token bundle: access, refresh, expiry, scope).
  - `WearableTokenStore` — generic Keychain store keyed per provider.
  - `FitbitDataSource` / `GoogleFitDataSource` — `WearableDataSource` conformers backed by REST.
  - `WearableConnectionManager` — `@Observable` that owns connect/disconnect/sync per provider and
    persists state into `Measurement`/`ActivityDaily`.
  - `MeasurementSource` gains `case fitbit, googleFit`.
  - Info.plist: `CFBundleURLTypes` custom scheme `pulseloop` for OAuth callback; config keys
    `FITBIT_CLIENT_ID`, `GOOGLE_CLIENT_ID` (real values injected at build; placeholders shipped).

## OAuth2 flow (both providers)
1. Build authorize URL with `client_id`, `redirect_uri = pulseloop://oauth-callback/<provider>`,
   `scope`, `response_type=code`, PKCE `code_challenge` (S256), `state`.
2. `ASWebAuthenticationSession(url:callbackURLScheme:"pulseloop")` → returns the redirect URL.
3. Exchange `code` + `code_verifier` at the token endpoint → access + refresh tokens.
4. Store the token bundle in Keychain (`WearableTokenStore`).
5. On each API call, refresh if expired (refresh_token grant).

### Endpoints
- **Fitbit:** authorize `https://www.fitbit.com/oauth2/authorize`, token
  `https://api.fitbit.com/oauth2/token` (PKCE, no client secret for public client). Data:
  `GET /1/user/-/activities/date/<date>.json` (steps), `GET /1/user/-/activities/heart/date/<date>/1d.json` (resting HR).
- **Google Fit:** authorize `https://accounts.google.com/o/oauth2/v2/auth`, token
  `https://oauth2.googleapis.com/token`. Data via `users/me/dataset:aggregate` for
  `com.google.step_count.delta` and `com.google.heart_rate.bpm`.

## Persistence mapping
- Steps → `ActivityDaily(date:, steps:, source: "fitbit" | "googlefit", syncedAt:)`, upsert by (date, source).
- Resting/latest HR → `Measurement(kind: .heartRate, source: .fitbit | .googleFit, timestamp:, value:)`.
- SpO2 (Fitbit) → `Measurement(kind: .spo2, ...)` when available.

## Testing
- Pure-logic tests (no network): PKCE verifier/challenge correctness; token-bundle Codable +
  Keychain round-trip (in-memory dict store injected); REST response → Measurement/ActivityDaily
  mapping decoders; expiry/refresh decision logic; ConnectorStatus mapping.
- Network calls are isolated behind a small `HTTPClient` protocol so sources are testable with a
  stub returning canned JSON.

## Decision log
- iOS "Google Health" = Google Fit REST API (OAuth2). Health Connect = Android-only, out of scope.
- Public-client PKCE (no embedded secret) for Fitbit; Google uses installed-app client (PKCE).
- Tokens in Keychain only; never in Info.plist/UserDefaults.
