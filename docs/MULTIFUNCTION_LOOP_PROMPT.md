# PulseLoop → Multifunction AI Chatbox — Loop Prompt

> **How to use this file.** Paste the section titled **"THE LOOP PROMPT"** (§4) into Claude (Cursor agent) as a single message at the start of each working session. Claude will pick up this roadmap, do exactly one iteration, update the tracker, and stop. Re-run it to advance the next iteration. Sections 0–3 + 5 are reference material the prompt points Claude at — keep them in the repo. This effort is a **sibling track** to `docs/LOOP_PROMPT.md` (the modular sub-app platform); it shares the same guardrails and the same Coach orchestrator, credits, and design-system seams.

---

## 0. North-Star Vision (the fixed mission — never changes between iterations)

Turn the PulseLoop **AI Coach chatbox** (`Views/CoachView.swift` + `Coach/`) into a **multifunction AI surface** — a single conversational interface that can do far more than answer questions about health data. Concretely, the chatbox can:

1. **Generate media in-chat.** Text-to-image, image-to-image (edit), and text-to-video, rendered as first-class cards in the assistant bubble, via **[muapi.ai](https://muapi.ai)** — a unified API exposing 100+ generative models (`flux-schnell`, `gpt-image`, `midjourney`, `seedream`, `veo3`, `kling-master`, etc.) behind one submit-then-poll workflow.
2. **Chat with / route to other models.** A model picker lets the user pick which LLM answers (e.g. the existing Bedrock Claude, OpenAI via BYO key, OpenRouter models through the legacy `AIService`, or a muapi text model), and the Coach can **delegate a sub-question to a different model** as a tool call and fold the answer back into its structured response.
3. **Stay on-brand and safe.** All new surfaces use the design system (`PulseColors`/`PulseFont`/`PulseCard`, SF Symbols, black primary buttons) and the Coach's strict-JSON structured-output contract. Generated media is shown through a fixed, declarative card catalog — never arbitrary HTML/Swift.
4. **Meter every AI action against credits.** Media generation and cross-model chat consume **AI credits** through the existing `CreditsLedger` + metering seam, with per-model cost estimates surfaced before expensive jobs (muapi exposes `estimate-cost`).
5. **Be robust & enterprise-quality.** Async job lifecycle (submit → poll → render → persist), cancellation, retry, graceful failure, content moderation on prompts, accessibility, and tests for the client + the new tools.

**Non-negotiables across every iteration:**
- The app must **always build and run** at the end of each iteration. Never leave `main` in a broken state.
- **Design system is law.** Every screen uses `PulseColors` / `PulseFont` / `PulseRadius` / `PulseLayout` and components from `App/AppTheme.swift` + `DesignSystem/Components.swift`. Follow `.cursor/rules/design-system.mdc`. **SF Symbols only, no emoji in rendered UI. Primary buttons are black, not accent.**
- **No secrets in source.** The muapi `x-api-key` lives in the **Keychain** (mirror `Coach/Config/OpenAIKeychainStore.swift` / `Coach/Bedrock/BedrockCredentialsStore.swift`), entered via Settings UI — never hard-coded, never committed.
- **Structured output only.** New chat capabilities extend the `coach_response` JSON schema (`Coach/Schema/CoachResponseSchema.swift`) + `CoachResponse`/`CoachResponseView`; they do not bypass the orchestrator with free-form rendering.
- **Credits everywhere AI runs.** Every media job and every cross-model delegation meters credits through `Services/CreditsLedger.swift`; estimate cost before submit where the provider supports it.
- **Backward compatible data.** SwiftData migrations are additive/lightweight; never drop user data. Persisted media references store URLs/metadata, not large blobs in the DB.

---

## 1. Codebase Context (real anchors — do not invent file names)

**Stack:** SwiftUI + SwiftData. Entry: `PulseLoop/PulseLoopApp.swift` → `RootAppView` (`PulseLoop/Views/RootViews.swift`).

**The AI chatbox today (what we're extending):**
- **UI:** `Views/CoachView.swift` — the chat screen: header, scrollback of `CoachMessage` bubbles (`CoachBubble`), cold-start prompt chips, composer, conversation history, personality picker. Backed by `Coach/ViewModels/CoachViewModel.swift` (one turn = `send(_:conversationId:context:)`).
- **Orchestrator:** `Coach/Orchestration/CoachOrchestrator.swift` — the agent loop (rounds, tool budget, retries, traces, `previousResponseId`). Selects a `ResponsesClient` per turn.
- **Clients (the `ResponsesClient` protocol seam):**
  - `Coach/OpenAI/OpenAIResponsesClient.swift` — OpenAI Responses API.
  - `Coach/OpenAI/BackendProxyResponsesClient.swift` — server-proxied (credit-enforcement seam).
  - `Coach/Bedrock/BedrockResponsesClient.swift` — AWS Bedrock (Claude) via SigV4; translates OpenAI Responses ⇄ Anthropic Messages and keeps client-side conversation state.
  - Client selection lives in `CoachViewModel.makeClient(apiKey:settings:)`.
- **Structured output:** `Coach/Schema/CoachResponseSchema.swift` (strict JSON schema) → `Coach/Schema/CoachResponse*.swift` (decoded type) → `Coach/Schema/CoachResponseView.swift` (renders title/summary/bullets/**chart**/notes/sources/follow-up chips). `Coach/Schema/CoachChart.swift` is the precedent for an **embedded structured card** in a response.
- **Tools:** `Coach/Tools/` — `CoachTool.swift` defines `AnyCoachTool` (name, description, JSON-schema `parameters`, `strict`, async `run`). Registered + gated in `Coach/Tools/ToolRegistry.swift` keyed off `Coach/Config/CoachFeatureFlags.swift`. Existing tool families: `RetrievalTools`, `ChartTools`, `AnalysisTools`, `ActionTools`, `MemoryTools`, `WebSearchTool`, `SubAppBuilderTools`.
- **Settings:** `Coach/Config/CoachSettings.swift` (`CoachProviderMode`: `offlineStub` / `userOpenAIKey` / `backendProxy` / `bedrock`; per-provider model + region fields) and the editor `Coach/Config/CoachSettingsSection.swift`. Keys in Keychain via `OpenAIKeychainStore.swift` / `BedrockCredentialsStore.swift`.
- **Credits:** `Services/CreditsLedger.swift` (balance, metering, `syncAuthoritativeBalance`), `Services/CreditStore.swift` (StoreKit 2 packs), `AppRoute.credits` → `CreditsView`.
- **Legacy AI (multi-model precedent):** `Services/AIService.swift` — OpenRouter (OpenAI-compatible), Keychain key (`OpenRouterKeychainStore`), used by `CommandPaletteView`, meal/product scan, notes, inbox. Demonstrates calling **other models**; reuse its key-handling pattern, prefer routing new work through the Coach.

**Design system:** `App/AppTheme.swift` (`PulseColors`, `PulseFont`, `PulseRadius`, `PulseLayout`, `PulseCard`, `PrimaryButton`, `SecondaryButton`, `StatusChip`, …), `DesignSystem/Components.swift`, `DesignSystem/ChartViews.swift`. Law: `.cursor/rules/design-system.mdc`.

**Networking conventions:** plain `URLSession` + `async/await` + `Codable` (see `AIService.swift`, `BedrockResponsesClient.swift`, the muapi-adjacent `OpenFDAService.swift` / `OpenFoodFactsService.swift` / `ProductSearchService.swift`). No third-party networking deps.

**muapi.ai API surface (real — verified):**
- Base URL `https://api.muapi.ai/api/v1`. Auth header `x-api-key: <KEY>`.
- **Submit:** `POST /api/v1/{model}` with `Content-Type: application/json`, body `{ "prompt": "…", …model params }` → returns a `request_id`.
- **Poll:** `GET /api/v1/predictions/{request_id}/result` with `x-api-key` until `status == "completed"`; read result media URLs from `outputs[]` (images/MP4s on muapi CDN).
- **File upload (for image-to-X):** `POST /api/v1/upload_file` (`multipart/form-data`, `file=@…`) → hosted URL to pass as `image_url`.
- **Catalog (no key):** `GET /api/v1/models` → models + categories + per-call USD cost. Cost quote: `POST /api/v1/models/{name}/estimate-cost`.
- **Sandbox mode** returns a model's example media (free) — use it for tests + first integration so we never spend real credits in CI.
- **Webhooks** can replace polling for long video jobs (60–300s); polling-first is fine to start.
- Categories/models to expose first: image `flux-schnell` (fast/cheap) + `flux-dev`/`gpt-image`; video `seedance-lite`/`hunyuan` (cheap) + `veo3-fast`.

---

## 2. Architecture Target (what we are building toward)

### 2.1 `MuapiClient` (Services/MuapiClient.swift)
A small `async/await` client: `submit(model:params:) -> requestID`, `pollResult(requestID:) -> MuapiResult` (with bounded backoff + timeout + cancellation), `uploadFile(Data, filename:) -> URL`, `models() -> [MuapiModel]`, `estimateCost(model:params:) -> Credits`. Key resolved from Keychain (`MuapiKeychainStore`), env, or Info.plist — same fallback ladder as `AIService.resolvedAPIKey()`. Honors a **sandbox** flag for tests/first run.

### 2.2 Media generation as Coach tools
New `Coach/Tools/MediaTools.swift` exposing `AnyCoachTool`s the orchestrator can call: `generate_image`, `edit_image` (image-to-image via upload), `generate_video`. Each: validates + moderates the prompt, estimates + reserves credits, submits to muapi, polls, returns a `ToolResult` carrying the media URL(s) + metadata. Gated by a new `CoachFeatureFlags.mediaGenerationEnabled` (requires a muapi key).

### 2.3 Media card in the structured response
Extend `coach_response` with an optional `media` block (mirroring how `chart` is embedded): kind (`image`/`video`), URL(s), prompt, model, alt text. Decode in `CoachResponse`; render a `CoachMediaCardView` (design-system card: async image / inline video player, tap-to-expand, save/share, regenerate, "made with {model} · {credits}" footer). No new card type executes code.

### 2.4 Multi-model routing
- A **model picker** in `CoachView` (and `CoachSettings`) choosing the answering model across providers (Bedrock Claude / OpenAI / OpenRouter via `AIService` / a muapi text model). Drives `CoachViewModel.makeClient`.
- A `chat_with_model` tool so the Coach can **delegate** a sub-question to a named alternate model and fold its answer into the structured response (with attribution + credit metering).

### 2.5 Credits & safety
Every media job + cross-model delegation meters `CreditsLedger`; surface muapi `estimate-cost` before expensive (video) jobs and block when balance is insufficient (reuse `ResponsesError.insufficientCredits`). Prompt moderation reuses/extends `SubAppModerator`-style policy. Persist generated-media references (URL + metadata) on the `CoachMessage` (additive SwiftData field), never large blobs.

### 2.6 Robust async lifecycle
Submit→poll→render→persist with progress UI in the bubble, cancellation, retry on transient failure, and webhook-ready design for long video jobs.

---

## 3. Phased Roadmap (the ordered backlog the loop walks through)

Work strictly top-to-bottom. Each **Iteration** is small, shippable, and leaves the app building. Track status in `docs/MULTIFUNCTION_PROGRESS.md` (create it on iteration M1).

**Phase M — muapi foundation**
- M1. Create `docs/MULTIFUNCTION_PROGRESS.md` tracker. Add `MuapiKeychainStore` + a `Muapi` section in `CoachSettingsSection.swift` to enter/store/remove the `x-api-key` (Keychain). No generation yet.
- M2. `Services/MuapiClient.swift`: submit + poll + sandbox mode + cancellation/timeout + `Codable` result types. Add `MuapiModelCatalog` via `GET /api/v1/models`. Unit-test against **sandbox** responses.
- M3. `uploadFile` + `estimateCost` on the client; `CoachFeatureFlags.mediaGenerationEnabled` (true only when a muapi key exists).

**Phase N — media in chat**
- N1. `Coach/Tools/MediaTools.swift` → `generate_image` tool (sandbox-first), registered in `ToolRegistry` behind the new flag.
- N2. Extend `coach_response` schema with the optional `media` block + decode it in `CoachResponse`; build `CoachMediaCardView` (async image, expand, save/share, regenerate). Wire into `CoachResponseView`.
- N3. Persist generated media on `CoachMessage` (additive field). Credit metering on image jobs via `CreditsLedger`; insufficient-balance handling.
- N4. `generate_video` + `edit_image` (image-to-video / image-to-image via `upload_file`); inline video player card; `estimate-cost` confirmation before video submit.

**Phase O — multi-model**
- O1. Model picker UI in `CoachView` + `CoachSettings`; persist selection; drive `CoachViewModel.makeClient` across existing providers.
- O2. `chat_with_model` delegation tool (route a sub-question to an alternate model — incl. a muapi text model or OpenRouter via `AIService` — with attribution + metering).
- O3. Surface available models from the muapi catalog + provider list in the picker; per-model cost hints.

**Phase P — hardening**
- P1. Prompt moderation for media; cancellation/retry polish; webhook-ready long-job path; accessibility (VoiceOver alt text on media, Dynamic Type); tests for `MuapiClient`, `MediaTools`, schema decode, and credit metering.

---

## 4. THE LOOP PROMPT (paste this each session)

```
You are continuing a long-running project: turning the PulseLoop AI Coach chatbox
into a MULTIFUNCTION AI surface — generate media (images/video) in-chat via
muapi.ai and chat with / route to other models — all on the existing Coach
orchestrator, structured-output contract, credits ledger, and design system. Your
single source of truth is docs/MULTIFUNCTION_LOOP_PROMPT.md (mission §0, code
anchors §1, architecture target §2, roadmap §3, guardrails §5) and the live tracker
docs/MULTIFUNCTION_PROGRESS.md. The shared guardrails in docs/LOOP_PROMPT.md §5 and
.cursor/rules/design-system.mdc also apply.

Do EXACTLY ONE iteration, then stop. Follow this loop:

1. ORIENT. Read docs/MULTIFUNCTION_LOOP_PROMPT.md and docs/MULTIFUNCTION_PROGRESS.md.
   If MULTIFUNCTION_PROGRESS.md does not exist, create it from the §3 roadmap with
   every item set to "pending", then treat iteration M1 as current.

2. SELECT. Pick the single highest-priority "pending" iteration (top-to-bottom in
   §3). Restate it in one sentence. If it is too big for one safe, shippable step,
   split it: do the first sub-step now and add the remainder as new pending items.

3. PLAN. Write a short todo list for this iteration only. Identify the exact real
   files from §1 you will touch (never invent file paths — verify by reading). Reuse
   existing seams: the ResponsesClient protocol, AnyCoachTool + ToolRegistry +
   CoachFeatureFlags, the coach_response schema + CoachResponseView (chart is the
   precedent for an embedded card), CreditsLedger metering, and the Keychain key
   stores.

4. IMPLEMENT. Make the change. Obey every guardrail in §5. SF Symbols only, no emoji
   in UI, primary buttons black. No secrets in source — the muapi x-api-key lives in
   the Keychain, entered via Settings. Default to muapi SANDBOX mode for first
   integration and tests so no real credits are spent. New chat capabilities extend
   the structured-output contract and render through fixed design-system cards —
   never free-form HTML/Swift. Meter credits on every media job and cross-model
   delegation; estimate cost before video jobs.

5. VERIFY. Build the app and resolve errors before finishing:
   xcodebuild -scheme PulseLoop -destination 'generic/platform=iOS Simulator' build
   (use ReadLints on edited files; add/adjust tests where §3 calls for them — prefer
   testing the MuapiClient + tools against sandbox/mocked responses). The app MUST
   build at the end of the iteration.

6. RECORD. Update docs/MULTIFUNCTION_PROGRESS.md: mark this iteration done with a
   1–3 line summary of what changed and which files, list any follow-ups you spun
   off, and clearly name the NEXT pending iteration.

7. STOP. Post a concise summary: what you did, build status, and the next
   iteration. Do not start the next iteration. Do not create a git commit unless I
   explicitly ask.

Rules of engagement:
- Keep main always building; never leave broken state.
- Prefer small, reversible steps over big rewrites; gate new surfaces behind a
  feature flag so they stay invisible until configured (muapi key present).
- Backward-compatible, additive SwiftData migrations only — never drop user data;
  persist media as URLs + metadata, not blobs.
- If a decision has real product trade-offs (which models to default to, credit
  cost per generation, how media cards behave), state your default choice, proceed,
  and note it in the tracker for my review rather than blocking.
- If you discover the roadmap is wrong, propose the fix in the tracker and adjust,
  but still complete one concrete shippable step this iteration.
```

---

## 5. Guardrails (referenced by the loop — the hard rules)

- **Build green every iteration.** End state must compile and run. Use the Xcode build/lint as the gate.
- **Design system is law.** `PulseColors`, `PulseFont`, `PulseRadius`, `PulseLayout`, components from `App/AppTheme.swift` + `DesignSystem/Components.swift`. Obey `.cursor/rules/design-system.mdc`. SF Symbols only (no emoji in rendered UI). Primary buttons black, accent used sparingly. Media cards reuse `PulseCard` surfaces + hairline borders.
- **Security.** No API keys/secrets in source. The muapi `x-api-key` lives in the Keychain (`MuapiKeychainStore`, mirroring `OpenAIKeychainStore`/`BedrockCredentialsStore`), entered via the Settings UI. Never log full keys or commit them.
- **Structured output only.** Extend the `coach_response` schema + `CoachResponse`/`CoachResponseView` for new card types (media). Do not bypass the orchestrator with free-form rendering, raw HTML, or eval'd code. Media is shown through a fixed, declarative card catalog.
- **Credits everywhere AI runs.** Every media generation and every cross-model delegation meters `CreditsLedger`. Use muapi `estimate-cost` to quote (and confirm) before expensive/video jobs; block on insufficient balance using `ResponsesError.insufficientCredits`.
- **Provider-agnostic via the existing seam.** Add models/providers behind the `ResponsesClient` protocol + `CoachViewModel.makeClient` and `MuapiClient`; do not fork the orchestrator. Cross-model answers carry attribution.
- **Safety & moderation.** Moderate user prompts before submitting media jobs (reuse `SubAppModerator`-style policy). Respect content limits; surface failures gracefully (sandbox/example fallback in tests, never silent crashes).
- **Robust async.** Submit→poll→render→persist with bounded backoff, timeout, cancellation, and retry on transient errors. Design the long-video path to be webhook-ready even if polling-first.
- **Data integrity.** Additive, lightweight SwiftData migrations; defaulted new fields on `CoachMessage`; store media URLs + metadata, never large binaries in the DB. Never drop user data.
- **Accessibility & quality.** Dynamic Type, VoiceOver alt text on generated media, 44pt tap targets; add tests for `MuapiClient`, `MediaTools`, schema decode, and credit metering.
- **One iteration at a time.** The loop does a single shippable step and stops, keeping the project reviewable.
- **Don't disturb the modular track.** This is additive to `docs/LOOP_PROMPT.md`'s sub-app platform — reuse its seams (Coach, credits, design system), don't regress them.

