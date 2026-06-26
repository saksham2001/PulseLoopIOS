# Production E2E Loop — Progress

Tracking the "fully working, no test data, intuitive, all features work" loop.
Build target: iPhone 16 Pro simulator (Debug). Each tier is verified by a clean build.

## Status

| Tier | Scope | State |
| --- | --- | --- |
| 0 | Clean-slate correctness | Done |
| 1 | Onboarding name + personalization | Done |
| 2 | Home/Today real empty states | Done |
| 3 | Coach chat image input (multimodal) | Done |
| 4 | Settings & modules organization | Done |
| 5 | Full route/module sweep, bug fixes | Done |

## Tier 0 — Clean-slate correctness (Done)
- Verified `RootAppView.task` no longer auto-seeds demo data on a fresh install.
  Demo data only loads behind the `-seedDemo` launch arg / `seedDemo` default.
- A truly empty install shows `OnboardingFlowView`, then an empty app.
- Exercise catalog is treated as content (not demo data) and is seeded on empty installs.

## Tier 1 — Onboarding name (Done)
- Added an `OnboardingNameView` step (Welcome → **Name** → Health → Privacy → Comfort).
- Name is trimmed and persisted to `UserProfile.name` in `finish()`.
- `HomeView` greeting already reads `profiles.first?.name`, so it personalizes
  automatically once onboarding completes. Pre-fills if a name already exists.

## Tier 3 — Coach image input (Done)
- `CoachMessage.attachmentData` (external storage) persists an attached image for
  the transcript.
- Composer gains a "+" attach menu: **Photo Library** (`PhotosPicker`, up to 4) and
  **Take Photo** (`CameraView`, when a camera is available). Thumbnails show in a
  removable strip; send is enabled for image-only messages.
- `CoachViewModel.send(images:)` downscales/encodes each image to a base64 JPEG
  `data:` URL and threads them through `CoachOrchestrator.runTurn(imageDataURLs:)`.
- `OpenAIRequestBuilder.message(imageDataURLs:)` emits multimodal content parts
  (`text` + `image_url`); `OpenRouterResponsesClient` passes array content straight
  through to chat-completions.
- A turn carrying photos forces `AIModel.vision.resolvedSlug` so the image is read
  regardless of the user's chosen smart model.

## Tier 2 — Home/Today empty states (Done)
- Home modules are data-gated via `shouldShowModule` (Up Next/Tasks/Right Now/AI
  Digest/Inbox hide when their data is empty) rather than showing fake content.
- When no modules are installed, Home shows the `emptyShellCard`
  ("Install your first module").
- Confirmed no auto-seed: `SeedData.seed` is unused in the app path; demo data
  only loads behind `-seedDemo`.

## Tier 4 — Settings & modules organization (Done)
- Profile name is now **editable** in Settings (was read-only). New
  `profileNameField` persists to `UserProfile.name` on submit and on focus loss,
  honoring the onboarding promise that the name can be changed "anytime in Settings".
- Settings remains organized into clear sections: Appearance, Comfort, Fitness,
  Profile, Ring, Cloud Sync, Coach, AI Models, Voice, Tools, Data.

## Tier 5 — Route/module sweep + runtime smoke test (Done)
- Full `xcodebuild` of the app target compiles every view/route → **BUILD SUCCEEDED**.
- Runtime smoke test on iPhone 16 Pro simulator:
  - Clean install (no `-seedDemo`) → onboarding renders, including the new **Name**
    step with the Continue button correctly disabled until a name is entered.
  - `-seedDemo` launch → Home renders with personalized greeting ("Good afternoon,
    Rey"), the empty-shell module card, and Up Next; app runs without crashing.
- Unit tests: 13/14 pass in touched areas. The lone failure,
  `VoiceEngineCoordinatorTests.testKokoroRedirectVoicesProduceDistinctAudio`, is a
  pre-existing, environment-dependent assertion in the neural-voice synthesis domain
  (prior voice task) and unrelated to this loop's changes.

## Known follow-ups (out of this loop's diff)
- A CoreData log notes a missing App Group store path
  (`Application Support/default.store`) for the shared widget/watch container on a
  fresh simulator. Pre-existing; not triggered by these changes.
- `simctl` in this Xcode build can't drive taps/text, so deeper interactive flows
  (typing a name, picking a photo) were verified by code + static render rather than
  scripted UI automation.

## Verification log
- `xcodebuild ... -scheme PulseLoop -destination 'iPhone 16 Pro'` → **BUILD SUCCEEDED**
  after Tiers 0/1/3, and again after Tier 4.
- Clean install + `-seedDemo` launches verified via screenshots.
- `xcodebuild ... test` → only the unrelated Kokoro voice-distinctness test fails.

