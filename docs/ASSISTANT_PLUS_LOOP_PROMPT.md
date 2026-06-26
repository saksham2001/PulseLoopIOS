# Open-Loop Prompt — "Assistant: an intuitive, search-first, agentic chat with beautiful output"

> Paste this whole file to the agent as the brief. Work it as a continuous loop:
> one track at a time, smallest shippable change, **keep the iOS build + full test
> suite green every iteration**, append a dated entry to
> `docs/ASSISTANT_PLUS_PROGRESS.md`, and run on the simulator at the end. Do **not**
> stop until every track is done and acceptance is met.
>
> You are the founder of Perplexity. The chat in this app should feel like a
> world-class answer engine that **actually thinks, runs agents, searches the live
> web, plans, and renders a beautiful, scannable answer** — with real citations and
> generated imagery when a picture helps. Today it does none of that reliably: on
> the default model it literally replies *"I can't search… I'm having trouble with
> web searches right now."* (see the failing screenshot). Fix that first.

---

## ROLE & NORTH STAR

The in-app chat is the product's brain. A great turn:

1. **Thinks** — shows real, legible reasoning/steps (not a fake "2 steps" pill).
2. **Uses agents/tools** — calls the right tools in a loop to ground every claim.
3. **Searches the live web** — on **any** configured model/provider, reliably,
   with **inline citations** and a sources list. Never "I can't search."
4. **Plans** — for multi-part asks, lays out a short plan, executes it, then
   answers; organizes results into the right structure (Trip/task/note).
5. **Beautiful output** — a clean, scannable answer: a crisp headline, tight
   prose, source chips, optional cards (travel/chart/diagram), follow-up chips,
   and **generated images** (via Sora / "nano banana") when a picture adds value.

Design system is **non-negotiable**: follow `.cursor/rules/design-system.mdc`
(PulseColors/PulseFont, black primary buttons, hairline cards, SF Symbols only —
**no emoji in UI**, design-system sheets with detents + drag indicator).

---

## RENAME FIRST: "Coach" → "Assistant" (T0, do this before anything else)

The product is no longer a "Coach"; it is an **Assistant**. Rename all
**user-facing** strings and labels from "Coach"/"AI Coach" to "Assistant"/
"AI Assistant" across the app — chat header, Settings section titles, the AI
center button, notifications copy, empty states, onboarding, etc. The screenshot
header already shows "PulseLoop Assistant"; make everything else consistent.

- **User-facing copy only must change.** You may leave internal type/file names
  (`CoachOrchestrator`, `CoachResponse`, `CoachView`, `CoachViewModel`,
  `CoachPromptBuilder`, `CoachFeatureFlags`, `CoachSettings`, the `Coach/` folder)
  as-is to avoid a giant risky refactor — renaming symbols is optional and only if
  it stays green. Prioritize visible text.
- Search the codebase for visible occurrences: grep `"Coach"`, `"AI Coach"`,
  `"coach"` inside `Text(...)`, `navigationTitle(...)`, button labels, settings
  section headers, notification titles/bodies, and the system-prompt's
  self-reference (`CoachPromptBuilder` says "You are PulseLoop…" — make sure it
  refers to itself as the user's **Assistant**, not "Coach").
- Update `docs`/prompts' user-facing language where it surfaces in the app.
- Acceptance: no visible "Coach" anywhere in the running app; the assistant calls
  itself "Assistant"; build + tests green.

---

## THE BUG TO KILL (why search fails today — read before T1)

The hosted web-search tool is **OpenAI-Responses-only**:
`PulseLoop/Coach/Tools/WebSearchTool.swift` emits `{"type":"web_search"}`, and
`ToolRegistry.toolSpecs` appends it (`PulseLoop/Coach/Tools/ToolRegistry.swift:68`).
But the default provider is **OpenRouter** with `google/gemini-2.5-flash`
(`PulseLoop/Services/AIModel.swift:25`, `CoachFeatureFlags.model:97`), and
`OpenRouterResponsesClient.chatTools(...)` **drops every non-function (hosted)
tool** before the request (`PulseLoop/Coach/OpenAI/OpenRouterResponsesClient.swift:165-176`).

So on the shipping default path the model is handed **no search capability at
all**, yet the prompt tells it to "search the live web" → it apologizes ("I can't
search right now"). The hosted tool only works on the OpenAI Responses client
(`OpenAIResponsesClient`). **Fix: add a real, provider-agnostic `web_search`
function tool** that runs an actual search over the testable `HTTPTransport` seam,
so search works on Gemini/GLM/Claude/GPT alike.

---

## OPEN LOOP — TRACKS (do in order; one PR-sized change each)

### T1 — Provider-agnostic live web search (kills the "can't search" bug)
Make `web_search` a **function tool with a local handler** that works on every
provider, replacing reliance on the hosted-only tool.

- Add a `WebSearchProvider` protocol + `WebSearchResult` (title, url, snippet,
  publisher, published date) behind the testable `HTTPTransport` seam (mirror the
  Travel search layer: `PulseLoop/Services/Travel/TravelSearch.swift`,
  `TravelSearchConfig.swift`, `AmadeusFlightProvider.swift`).
- Implement a real provider against a search API (e.g. Brave Search API, Tavily,
  Bing, or SerpAPI — pick one with a simple REST + JSON contract). Read the key
  from `Info.plist` with placeholder gating (`REPLACE_WITH_YOUR_…`) exactly like
  `TravelSearchConfig.isPlaceholder`. Add a `WEB_SEARCH_*` key to `Info.plist`.
- Add a `search_web` (or keep the name `web_search` but as a **function** tool)
  coach tool in `Coach/Tools/` that takes `query` (+ optional `recency`,
  `count`), calls the provider, and returns normalized results the model must turn
  into an answer **with citations**. Register it in `ToolRegistry` gated by
  `flags.webSearchEnabled`.
- **Keep the hosted tool only for the OpenAI Responses path**: when the provider
  is OpenAI Responses, prefer the hosted `web_search` (it's higher quality); on
  OpenRouter/Bedrock, use the function tool. The orchestrator/registry must add
  exactly one working search path per provider — never zero.
- Degrade gracefully: if no key is configured, the tool returns
  `configured:false` with guidance, and the prompt tells the model to be honest
  ("I don't have live web access configured") instead of hallucinating.
- Tests: provider request-build + JSON parse over a stubbed transport;
  `isConfigured` gating; the tool's normalized output; registry includes a search
  tool for each provider mode. Build + tests green.

### T2 — Citations & sources rendering (Perplexity-style)
Make sources first-class in the answer.

- `CoachResponse` already has `sources: [{title,url,publisher}]` (see
  `OpenRouterResponsesClient.coachJSONInstruction`) — ensure the schema
  (`Coach/Schema/CoachResponse.swift`, `CoachResponseSchema.swift`) carries them
  and that the search tool's results flow into `sources`.
- Render a tasteful **Sources** section in `CoachResponseView.swift`: numbered,
  tappable source chips/rows (favicon or publisher initial in a `fillSubtle`
  rounded square, title + publisher, opens the URL). Inline `[1]`-style citation
  markers in prose are a plus. Design-system styled, no emoji.
- The prompt MUST instruct: when you used search, cite the specific sources you
  used and populate `sources`; don't cite what you didn't read.
- Tests: a response with sources renders the section; empty sources hides it.

### T3 — Real "thinking" / plan + steps (replace the fake "2 steps" pill)
The collapsible step disclosure is driven by the tool trace
(`CoachToolCallTrace`, `CoachTraceEvent`, rendered around `CoachResponseView`).
Make it genuinely reflect the agent's plan and actions.

- For multi-step asks, have the model emit a short **plan** (3-6 steps) up front
  (add a `plan: [String]?` to `CoachResponse` or reuse `bullets` with a
  `response_type` like `plan_then_answer`). Render the plan + the live
  tool-trace ("Searching the web", "Reading 4 sources", "Drafting answer") in the
  expandable steps panel with real labels + statuses (already partly in
  `CoachOrchestrator.onTrace`).
- Show a streaming "thinking…" state that lists steps as they happen, then
  collapses to "N steps" once done, expandable to the real trace (timings,
  tool names, redacted args, result summaries — all already captured in
  `CoachToolCallTrace`). No fabricated counts.
- Tests: trace with N tool calls yields "N steps"; plan renders when present.

### T4 — Agentic depth: plan → search → synthesize, with sane budgets
Tune the loop in `CoachOrchestrator` so it behaves like an answer engine.

- Allow enough rounds for multi-hop research (raise `maxRounds`/`maxToolCalls`
  defaults in `CoachSettings` sensibly; keep them user-configurable and credit-
  metered). Encourage **parallel** searches when sub-questions are independent.
- Prompt the model to: decompose → search each sub-question → read results →
  synthesize a single grounded answer → cite. Forbid answering external/current
  questions from memory without searching first.
- Keep the strict-JSON final contract working across providers (the repair loop
  in `parseFinal` + `coachJSONInstruction` already exist) — don't regress it.
- Tests: an orchestrator turn with a stubbed client + stubbed search tool runs
  multiple rounds and produces a grounded final with sources.

### T5 — Beautiful output polish (answer card)
Elevate `CoachResponseView` to a clean answer surface.

- Strong serif headline (`PulseFont.title`), tight body prose, a divider before
  Sources, source chips, follow-up chips as tappable pills, and graceful
  rendering of any attached card (travel/chart/diagram/media) — all on hairline
  cards, generous whitespace, monochrome. Match `.cursor/rules/design-system.mdc`.
- Follow-up chips must be **contextual to the topic** (reuse the existing
  `follow_up_chips`), not health nudges.
- Tests/build: snapshot-free — assert the view builds and key subviews appear for
  each `response_type`.

### T6 — Image generation via Sora / "nano banana" (pictures for chat & modules)
When a picture genuinely helps (a destination hero shot, a concept illustration,
a recipe plating, a module/trip cover), generate one.

- Extend `MuapiCatalog` (`PulseLoop/Services/MuapiClient.swift:366`) to add:
  - **"nano banana"** → Google **Gemini 2.5 Flash Image** (fast, cheap, great for
    in-chat illustrations) as an image model, and make it (or `flux-schnell`) the
    default for quick in-chat images.
  - **Sora** → OpenAI **Sora** as a video model in the video catalog, used only
    when the user explicitly asks for a video.
  - Confirm the muapi model identifiers are correct for the API; keep
    placeholder-safe + sandbox-free behavior (`muapiSandbox`) so tests don't spend.
- The `generate_image` / `generate_video` tools already exist
  (`Coach/Tools/MediaTools.swift`) and render via `CoachMediaCardView`. Make sure:
  - The Assistant proactively offers/uses `generate_image` when a visual clearly
    helps (and the user hasn't said "no images"), defaulting to **nano banana**.
  - The prompt explains when to prefer nano banana (quick illustration) vs a
    higher-fidelity model (user asked for quality), and Sora only for explicit
    video requests.
- **Modules/trip imagery:** wire generated images into module/trip visuals where
  a cover is missing — e.g. when a `Trip` has no `coverImageURL`, the Assistant
  can generate a destination hero and set it (reuse Travel's `coverImageURL`;
  travel cards already support `thumbnailURL`). Provide a small, design-system
  "Generate image" affordance where a cover/thumbnail slot is empty.
- Gating/credits: respect `flags.mediaGenerationEnabled`, the muapi key, the
  moderation pass (`MediaModerator`), and `CreditsLedger` metering — all already
  present. Sandbox stays free.
- Tests: catalog contains nano-banana (image) + sora (video) with sane defaults;
  `generate_image` returns a `media` object in sandbox; module/trip cover
  generation sets the URL. Build + tests green.

### T7 — Prompt rewrite ("Assistant", search-first, agentic, beautiful, images)
Rewrite `CoachPromptBuilder.systemPrompt` to encode all of the above.

- Identity: "You are the user's **Assistant** — an intuitive, search-first answer
  engine." (Not "Coach".) Keep the existing "stay on the user's topic, health is
  one feature not the identity" directives from
  `universal_assistant_open_loop_prompt.md`.
- Mandate: search the live web for anything external/current using `web_search`/
  `search_web`; **never** say you can't search when a search tool is enabled —
  call it. Cite sources. Decompose + plan multi-part asks. Organize results.
- Output contract: a crisp title, scannable prose, `sources` when search was used,
  contextual `follow_up_chips`, cards only when they fit, and `generate_image`
  (nano banana) when a picture adds real value. No emoji. Be honest about limits.
- Keep it provider-portable (it must work on Gemini/GLM/Claude/GPT through the
  OpenRouter chat-completions bridge and on the OpenAI Responses path).

### T8 — Verify end-to-end on the failing case
Reproduce the screenshot's flow ("Search best Bali restaurants") on the default
model and confirm the Assistant now: shows a plan/steps, actually searches, lists
real restaurants with citations, optionally a generated Bali hero image, and
offers contextual follow-ups — with no "I can't search" anywhere.

- Run on the simulator; capture that this specific prompt works.
- Full test suite green.

---

## TOOLS & FILES YOU'LL TOUCH (grounding)

- Orchestration loop: `PulseLoop/Coach/Orchestration/CoachOrchestrator.swift`
  (rounds at `:118`, budgets via `flags.maxRounds/maxToolCalls`).
- Provider bridge (drops hosted tools): `Coach/OpenAI/OpenRouterResponsesClient.swift:165`.
- Hosted-only search: `Coach/Tools/WebSearchTool.swift`; registry add at
  `Coach/Tools/ToolRegistry.swift:68`.
- Model/provider selection: `Services/AIModel.swift`, `Coach/Config/CoachFeatureFlags.swift`,
  `Coach/Config/CoachSettings.swift`, provider clients in `Coach/OpenAI/` + `Coach/Bedrock/`.
- Response schema/render: `Coach/Schema/CoachResponse.swift`, `CoachResponseSchema.swift`,
  `CoachResponseView.swift`; trace types `Coach/ViewModels/CoachTraceEvent.swift`.
- Prompt: `Coach/Context/CoachPromptBuilder.swift`.
- Media gen: `Coach/Tools/MediaTools.swift`, `Services/MuapiClient.swift`
  (`MuapiCatalog` at `:366`), `Coach/Schema/CoachMedia.swift` + `CoachMediaCardView.swift`,
  `Coach/Tools/MediaModerator.swift`.
- Testable search seam to mirror: `Services/Travel/TravelSearch.swift` + providers.
- Chat UI/header (rename target): `Views/CoachView.swift`, `Views/SettingsView.swift`,
  `Coach/Config/CoachSettingsSection.swift`, notification copy in `Coach/Notifications/`.

---

## HARD ACCEPTANCE (the whole loop)

- [ ] No visible "Coach" in the running app; it presents as the **Assistant**.
- [ ] On the **default** model (OpenRouter / Gemini 2.5 Flash), asking for
      anything external triggers a **real web search** with **cited sources** —
      the "I can't search / having trouble with web searches" reply is gone.
- [ ] Multi-part asks show a genuine **plan + steps** backed by the real tool
      trace; the "N steps" disclosure reflects actual tool calls (no fabrication).
- [ ] Answers are **beautiful & scannable**: title, tight prose, source chips,
      contextual follow-ups, cards only when they fit — all per the design system,
      **no emoji in UI**.
- [ ] The Assistant generates images when a picture helps, defaulting to
      **nano banana** (Gemini 2.5 Flash Image); **Sora** is used only for explicit
      video requests; missing module/trip covers can be generated and set.
- [ ] Graceful, honest degradation when a key isn't configured (never bluff).
- [ ] iOS builds green and the **full test suite passes** every iteration; new
      logic (search provider, citations, catalog, orchestrator paths) is
      unit-tested. Runs on the simulator at the end.

---

## WORKING AGREEMENT

- One track per iteration, smallest shippable change, build + tests green before
  moving on. Append a dated line to `docs/ASSISTANT_PLUS_PROGRESS.md` each time.
- Reuse existing seams (HTTPTransport, MuapiClient, CoachMedia, sources field,
  tool trace) instead of inventing parallel ones.
- API keys via `Info.plist` placeholders + `isConfigured` gating; sandbox/tests
  never spend real credits.
- Follow `.cursor/rules/design-system.mdc` for **every** pixel.
- Do not stop until all tracks are done and acceptance is met.
```
