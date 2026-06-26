# Assistant+ Progress

Loop: `docs/ASSISTANT_PLUS_LOOP_PROMPT.md` — make the in-app chat an intuitive,
search-first, agentic Assistant with beautiful output + generated imagery.

## 2026-06-24
- **T0 — Rename Coach → Assistant (user-facing).** Updated all visible strings:
  Settings section ("AI Assistant", "Assistant memory"), chat composer
  placeholder ("Ask the assistant..."), personality screen title, onboarding
  subtitles, Today ("Ask Assistant"), Credits/SubAppBuilder/KnowledgeBase/
  ConnectAccounts copy, AIModel tier title ("Assistant & chat"), CreditsLedger
  label ("Assistant chat"), and user-facing error/status strings (ResponsesErrors,
  CoachFeatureFlags status line, CoachFallbacks, MediaTools/ModelDelegation/Muapi
  key prompts, navigate_to notes). Internal type/file/keychain/notification/schema
  identifiers left unchanged to avoid a risky refactor. Build green.
- **T1 — Provider-agnostic live web search.** Root-caused "I can't search": the
  hosted `web_search` tool is OpenAI-Responses-only and the OpenRouter bridge
  (`OpenRouterResponsesClient.chatTools`) strips all hosted tools, so on the
  shipping default (OpenRouter+Gemini) the model had NO search. Added a real
  `search_web` function tool over the testable `HTTPTransport` seam:
  `Services/Search/WebSearch.swift` (provider protocol + `WebSearchResult` →
  `CoachSource`), `BraveWebSearchProvider.swift` (Brave Search REST, freshness,
  tag-stripping, parse), `LiveWebSearch.swift` facade, `Coach/Tools/SearchTools.swift`
  (`search_web` tool with configured/no-results/error degradation). Registered in
  `ToolRegistry` when `webSearchEnabled`; removed the dead hosted-spec append.
  Added `WEB_SEARCH_API_KEY` (Info.plist, placeholder-gated via TravelSearchConfig).
  Prompt now instructs `search_web` + honest degradation. 13 new tests; full
  suite green (392 passed, 1 skipped).
- **T2 — Citations & sources rendering.** Rewrote `CoachResponseView`'s sources
  block into a Perplexity-style numbered, tappable list (index badge + title +
  publisher + open affordance, design-system styled, divider above). Added a
  citation safety net in `CoachOrchestrator`: it collects sources from every
  `search_web` result and backfills `response.sources` (deduped by URL, capped 6)
  when the model forgets — so a searched answer ALWAYS shows where it came from.
  Helpers `sources(fromSearchResult:)` + `dedupedSources(_:limit:)` unit-tested.
- **T3 — Real plan + steps.** Rewrote `CoachTraceStrip` from a single "Thinking…"
  line into a Perplexity-style vertical step list collapsed from the genuine
  orchestrator trace (think → search → analyze → write). Each step shows a status
  icon: checkmark when done, spinner on the active step, warning on failure, plus
  a header ("Working · N steps · Ns"). Steps de-dupe tool running→completed pairs
  into one row. Build green.
- **T4 — Agentic depth.** Verified budgets support multi-hop research (defaults:
  8 tool calls / 4 rounds — room for several searches + analyze + synthesis). The
  orchestrator's tool loop already drives plan→search→search→synthesize; added a
  prompt directive to PLAN then RESEARCH with multiple refined queries (one per
  sub-question) and synthesize one grounded answer, plus a "Planning the approach…"
  opening trace. CoachTests (agentic loop) green.
- **T5 — Beautiful answer-card polish.** Delivered largely via T2/T3: numbered
  source rows with badges + divider, stepped trace list, consistent 10pt vertical
  rhythm in `CoachResponseView` (title → summary → bullets → chart/diagram/media →
  travel cards → notes → sources → chips). Build green.





