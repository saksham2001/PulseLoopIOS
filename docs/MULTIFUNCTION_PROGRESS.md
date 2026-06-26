# Multifunction AI Chatbox — Progress Tracker

> Live tracker for `docs/MULTIFUNCTION_LOOP_PROMPT.md`. One iteration per loop run.
> Sibling track to `docs/MODULAR_PROGRESS.md`; shares Coach/credits/design-system seams.

**Current iteration:** complete
**Last completed:** P1

---

## Phase M — muapi foundation
- **M1 — muapi key store + settings field — done**
- **M2 — MuapiClient (submit/poll/sandbox/cancel) + model catalog + tests — done**
- **M3 — uploadFile + estimateCost + mediaGenerationEnabled wiring — done**

## Phase N — media in chat
- **N1 — `generate_image` MediaTool behind flag — done**
- **N2 — `coach_response.media` block + `CoachMediaCardView` — done**
- **N3 — persist media on `CoachMessage` + credit metering — done**
- **N4 — `generate_video` + `edit_image` + video card — done**

## Phase O — multi-model
- **O1 — model picker UI driving `makeClient` — done**
- **O2 — `chat_with_model` delegation tool — done**
- **O3 — surface muapi catalog + provider list in picker — done**

## Phase P — hardening
- **P1 — moderation, retry, accessibility, tests — done**

> Roadmap complete. Full test suite green (126 tests, 0 failures).

---

## Log

### M1 — muapi key store + settings field (done)
- Added `Services/MuapiKeychainStore.swift` (`APIKeyStore` conformer, generic-password
  Keychain, mirrors `OpenAIKeychainStore`). The muapi `x-api-key` never lives in source.
- `Coach/Config/CoachSettings.swift`: new `enableMediaGeneration` (default on) +
  `muapiSandbox` (default on — free example media, no spend) fields with tolerant decode.
- `Coach/Config/CoachFeatureFlags.swift`: new `mediaGenerationEnabled` (true only when
  enabled in settings AND a muapi key is present in the Keychain).
- `Coach/Config/CoachSettingsSection.swift`: "Media generation" + "Sandbox mode" toggles
  and a `muapiField` (enter/update/remove key in Keychain, show/hide), mirroring the
  OpenAI key field styling.
- Build: green.
- Next: **M2** — `MuapiClient` (submit-then-poll, sandbox, cancellation/timeout) +
  model catalog + sandbox/mocked unit tests.

#### Caveats / follow-ups
- Media generation defaults to **sandbox on** so nothing spends real credits until the
  user opts out; revisit default once metering (N3) lands.

### M2 — MuapiClient + catalog + tests (done)
- `Services/MuapiClient.swift`: transport-injectable async client. `submit` (POST
  `/api/v1/{model}` → request_id), `pollResult` (GET `/predictions/{id}/result` until
  completed, with cancellation + timeout), `generate` (submit+poll), `models()` catalog.
  Sandbox sets `x-sandbox: true`. `extractOutputs` normalizes muapi's varied result
  shapes (`outputs:[url]`, `outputs:[{url}]`, top-level `output`).
- `MuapiCatalog`: curated default image/edit/video models + `defaultModel(for:)` +
  `cost(for:)`, so the picker works offline.
- `PulseLoopTests/MuapiClientTests.swift`: 10 tests (submit→poll, processing→complete,
  sandbox header, missing key, HTTP error, output normalization, catalog parsing,
  cancellation, timeout). All green.

### M3 — upload + cost estimate + credit kind (done)
- `MuapiClient.uploadFile(data:fileName:mimeType:)` (multipart → hosted URL) for
  image-to-image inputs; `estimateCost(model:)` from the curated catalog.
- `Services/CreditsLedger.swift`: new `AIUsageKind.mediaGeneration` (cost 3 — pricier
  than chat; video is the dominant cost).

### N1–N4 — media tools + media card (done)
- `Coach/Tools/MediaTools.swift`: `generate_image`, `generate_video`, `edit_image`
  tools (strict schemas, default-model fallbacks). Each submits via `MuapiClient`,
  polls to completion, returns a `media` object for the model to copy into
  `coach_response.media`. Honors `muapiSandbox`; meters `.mediaGeneration` only on real
  (non-sandbox) generations. Registered in `ToolRegistry` behind `mediaGenerationEnabled`.
- `Coach/Schema/CoachMedia.swift`: `CoachMedia` (kind/urls/prompt/model/sandbox),
  lenient decode. Added `media: [CoachMedia]` to `CoachResponse` (lenient, like `cards`)
  and to the strict `CoachResponseSchema` (required array, maxItems 4).
- `Coach/Schema/CoachMediaCardView.swift`: renders images (`AsyncImage`) and video
  (`VideoPlayer`), caption, model row, sandbox badge, share/open. Wired into
  `CoachResponseView` after the chart.
- Persistence: media rides `CoachResponse.encodedJSON()` → `CoachMessage.cardsJSON`,
  decoded back in `CoachView`. Round-trip + backward-compat tests added to `CoachTests`.
- Build + tests green.
- Next: **O1** — model picker UI driving `makeClient`.

#### Caveats / follow-ups
- Explicit **pre-spend cost confirmation** for expensive video (route through the
  orchestrator's `PendingAction` confirm flow) deferred to P1.

### O1–O3 — multi-model (done)
- `Views/CoachView.swift`: header `modelPicker` `Menu` lets the user switch the active
  provider; only configured providers are selectable; writes `settings.providerMode`
  which `CoachViewModel.makeClient` already reads per turn (drives `makeClient`).
- `Coach/Tools/ModelDelegationTools.swift`: `chat_with_model` tool — delegates a focused
  sub-question to a muapi text model and returns the answer for the Coach to attribute.
  Gated by `mediaGenerationEnabled`, honors sandbox, meters a `.coachTurn` on real calls.
- `MuapiClient.generateText` + `extractText` (varied text result shapes) + `MuapiCatalog.text`
  (gpt-4o, claude-3-7-sonnet, deepseek-v3, gemini-2-flash).
- Tests for `extractText` + text catalog. All 12 Muapi tests green.
