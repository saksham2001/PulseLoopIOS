# Release Build Checklist (iOS)

Pre-submission checklist for shipping PulseLoop to the App Store. Work top to
bottom; everything here is required for a clean review and a crash-free launch.

## 1. Signing & identifiers

- [ ] **Bundle ID** matches the App Store Connect record (`xyz.sakshambhutani.PulseLoop`).
- [ ] **Team / automatic signing** selected for the Release configuration.
- [ ] **App group** `group.xyz.sakshambhutani.PulseLoop` exists in the provisioning
      profile (used by the Live Activity + Watch targets).
- [ ] **Version (CFBundleShortVersionString)** bumped and **build (CFBundleVersion)**
      monotonically increasing.

## 2. Capabilities & entitlements

`PulseLoop.entitlements`:

- [ ] `com.apple.developer.healthkit` — HealthKit read/write.
- [ ] `com.apple.security.application-groups` — shared container.

Background modes (`Info.plist → UIBackgroundModes`): `location`,
`bluetooth-central`, `fetch`, `processing`. `BGTaskSchedulerPermittedIdentifiers`
includes `com.pulseloop.coach.refresh`.

- [ ] Every background mode is actually used (location during workouts, BLE for the
      ring, fetch/processing for coach refresh) — Apple rejects unused modes.

## 3. Usage descriptions (purpose strings)

Every API the app touches must have a clear, specific purpose string, or iOS
crashes on first use. Currently present and required:

- [ ] `NSCameraUsageDescription` — label scanning.
- [ ] `NSMicrophoneUsageDescription` — voice capture.
- [ ] `NSSpeechRecognitionUsageDescription` — dictation.
- [ ] `NSHealthShareUsageDescription` / `NSHealthUpdateUsageDescription` — HealthKit.
- [ ] `NSLocationWhenInUseUsageDescription` — GPS workout mapping.
- [ ] `NSLocationAlwaysAndWhenInUseUsageDescription` — background route recording
      (the recorder calls `requestAlwaysAuthorization()` + `allowsBackgroundLocationUpdates`).
- [ ] `NSBluetoothAlwaysUsageDescription` — `CBCentralManager` ring connection
      (required on iOS 13+; the app crashes at manager init without it).

> ⚠️ These last three were **added in F3** — they were missing and would have
> crashed the app the moment a workout requested location or the ring scan
> initialized Core Bluetooth.

## 4. Secrets

- [ ] `Info.plist → OPENROUTER_API_KEY` is the `REPLACE_WITH_YOUR_OPENROUTER_KEY`
      placeholder (the real key must live on the server proxy, not in the binary).
- [ ] `PULSELOOP_WEB_URL` points at the production backend (not localhost).
- [ ] Server env set: `OPENROUTER_API_KEY`, `DATABASE_URL`, Clerk keys, `APP_STORE_*`.
- [ ] The previously committed live key has been **revoked** and scrubbed from git
      history (see the security note in `DELIVERY_PROGRESS.md`).

## 5. Build hygiene

- [ ] Release build succeeds for a generic device:
      `xcodebuild -scheme PulseLoop -configuration Release -destination 'generic/platform=iOS' build`
- [ ] No `#if DEBUG`-only surfaces leak into Release (Debug menu, demo-data
      reseed, component gallery are all DEBUG-gated — see A1).
- [ ] Full test suite green: `xcodebuild -scheme PulseLoop -destination '<sim>' test`.
- [ ] No console `fault`/`error` logs on a clean cold launch.

## 6. Functional smoke (on device)

- [ ] Fresh install → onboarding → empty catalog.
- [ ] Pair the ring over BLE; live HR/SpO₂ render.
- [ ] Record a GPS workout; route + distance captured; resumes after screen-off.
- [ ] Connect to web (consent gate → pairing code → "Signed in as <email>").
- [ ] After connect/"Sync now", the web app reflects the device: `/dashboard`
      metrics populate and `/tasks` shows the same to-dos as the app (W4 sync).
- [ ] Buy a credit pack (StoreKit sandbox) → balance updates from the server.
- [ ] Coach turn debits credits via the proxy; out-of-credits opens the paywall.
- [ ] Export data (local + web) produces valid JSON; delete flows work.
- [ ] Diagnostics toggle off by default; turning it on starts MetricKit.

## 7. App Store Connect metadata

- [ ] Screenshots for all required device sizes.
- [ ] Privacy "nutrition label" matches `web/privacy`: health data (cloud sync,
      opt-in), diagnostics (opt-in, content-free), purchases.
- [ ] Privacy policy URL set to the hosted `/privacy` page.
- [ ] In-app purchase products created + "Ready to Submit" (see `BILLING_SETUP.md`).
- [ ] Age rating, category, support URL, and review notes (sandbox test account)
      provided.
