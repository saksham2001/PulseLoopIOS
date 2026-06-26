/**
 * Server-side bridge from the OpenAI **Responses**-shaped request the iOS Coach
 * orchestrator builds onto **OpenRouter**'s (stateless) chat-completions endpoint —
 * a TypeScript port of the app's `OpenRouterResponsesClient`.
 *
 * The orchestrator speaks the Responses API: it sends `{model, input, tools,
 * text.format, previous_response_id}` and expects a Responses-shaped reply
 * (`{id, output:[...], usage}`), using `previous_response_id` for conversation
 * state. OpenRouter has neither `/v1/responses` nor server-side state, so we:
 *   1. translate each request to chat-completions, and
 *   2. translate each reply back to the Responses shape.
 *
 * Conversation state (the growing `messages[]` history that the on-device actor
 * keeps) is handled by the route via {@link CoachSessionStore}, keyed on the
 * response id we return so the next turn's `previous_response_id` can resume it.
 */

export const OPENROUTER_CHAT_URL =
  "https://openrouter.ai/api/v1/chat/completions";

// Default model when a request omits one — mirrors iOS AIModel.smart.defaultSlug.
export const DEFAULT_COACH_MODEL = "google/gemini-2.5-flash";

// Models that don't support function/tool calling (or do so too unreliably for
// the agent loop). The Coach is tool-driven, so a request asking for one of
// these is coerced to a safe tool-capable default — otherwise the model returns
// prose the orchestrator can't parse and the turn fails. Mirrors the iOS
// `AIModel.toolIncompatibleSlugs`.
const TOOL_INCOMPATIBLE_MODELS = new Set<string>(["google/gemma-3-27b-it"]);

export type ChatMessage = Record<string, unknown>;

/** A single Responses output item, in the shape `OpenAIResponse.parse` reads. */
type ResponsesOutputItem =
  | {
      type: "message";
      role: "assistant";
      content: { type: "output_text"; text: string }[];
    }
  | {
      type: "function_call";
      name: string;
      call_id: string;
      arguments: string;
    };

export interface TranslatedRequest {
  model: string;
  body: Record<string, unknown>;
  /** The chat-completions messages appended by THIS request (incl. resumed history). */
  messages: ChatMessage[];
  wantsStructured: boolean;
}

/**
 * Append a system message describing the required `coach_response` JSON shape —
 * used in place of a provider-specific strict schema so the loop works across
 * Gemini/GLM/Claude/GPT (verbatim from the iOS client).
 */
export const COACH_JSON_INSTRUCTION = `IMPORTANT OUTPUT CONTRACT: Every time you reply to the user (including simple greetings), your message content MUST be ONLY a single JSON object — no markdown, no code fences, no text before or after. Use this exact shape:
{
  "response_type": one of "insight","insight_with_chart","question","action_confirmation","data_missing","safety_guidance","error_recovery",
  "title": string (<= 90 chars),
  "summary": string (<= 900 chars),
  "bullets": array of strings (<= 5),
  "chart": null,
  "safety_note": string or null,
  "data_quality_note": string or null,
  "sources": array of {"title": string, "url": string, "publisher": string},
  "follow_up_chips": array of strings (<= 4),
  "actions_taken": array of strings,
  "confidence": one of "low","medium","high",
  "media": [],
  "diagram": null
}
Every key is required. To call a tool, use the normal tool-call mechanism (not JSON in content). Only your FINAL textual answer must be this JSON object.`;

/** Convert Responses `input` items into chat-completions messages. */
export function ingestInput(
  input: Record<string, unknown>[],
  pendingToolCalls: ChatMessage[],
): { messages: ChatMessage[]; consumedPending: boolean } {
  const messages: ChatMessage[] = [];
  let consumedPending = false;

  const toolOutputs = input.filter(
    (i) => i.type === "function_call_output",
  );
  // Tool results must follow the assistant message that requested them.
  if (toolOutputs.length > 0 && pendingToolCalls.length > 0) {
    messages.push({
      role: "assistant",
      content: null,
      tool_calls: pendingToolCalls,
    });
    consumedPending = true;
  }

  for (const item of input) {
    if (item.type === "function_call_output") {
      messages.push({
        role: "tool",
        tool_call_id: typeof item.call_id === "string" ? item.call_id : "",
        content: typeof item.output === "string" ? item.output : "",
      });
    } else if (typeof item.role === "string") {
      // Responses uses a `developer` role; chat-completions uses `system`.
      const mapped = item.role === "developer" ? "system" : item.role;
      messages.push({ role: mapped, content: item.content ?? "" });
    }
  }

  return { messages, consumedPending };
}

/** Flat Responses function specs → nested chat-completions specs (drop hosted tools). */
function chatTools(
  tools: Record<string, unknown>[],
): Record<string, unknown>[] | null {
  const functions = tools
    .filter((t) => t.type === "function" && typeof t.name === "string")
    .map((spec) => {
      const fn: Record<string, unknown> = { name: spec.name };
      if (typeof spec.description === "string") fn.description = spec.description;
      if (spec.parameters && typeof spec.parameters === "object") {
        fn.parameters = spec.parameters;
      }
      return { type: "function", function: fn };
    });
  return functions.length > 0 ? functions : null;
}

/** Whether the request asked for a json_schema text format. */
function wantsStructuredOutput(text: unknown): boolean {
  if (!text || typeof text !== "object") return false;
  const format = (text as { format?: unknown }).format;
  if (!format || typeof format !== "object") return false;
  return (format as { type?: unknown }).type === "json_schema";
}

/**
 * Build the chat-completions body for one turn. `history` is the prior
 * conversation (from the session store) onto which this request's new messages
 * are appended; the merged array is returned so the caller can persist it.
 */
export function buildChatRequest(
  responsesBody: Record<string, unknown>,
  history: ChatMessage[],
  pendingToolCalls: ChatMessage[],
  didInjectJSONInstruction: boolean,
): TranslatedRequest & { injectedJSON: boolean; consumedPending: boolean } {
  const requestedModel =
    typeof responsesBody.model === "string" && responsesBody.model
      ? responsesBody.model
      : DEFAULT_COACH_MODEL;
  // Coach turns require tool calling; coerce known-incompatible models.
  const model = TOOL_INCOMPATIBLE_MODELS.has(requestedModel)
    ? DEFAULT_COACH_MODEL
    : requestedModel;

  const input = Array.isArray(responsesBody.input)
    ? (responsesBody.input as Record<string, unknown>[])
    : [];
  const { messages: incoming, consumedPending } = ingestInput(
    input,
    pendingToolCalls,
  );

  const messages = [...history, ...incoming];

  const rawTools = Array.isArray(responsesBody.tools)
    ? (responsesBody.tools as Record<string, unknown>[])
    : [];
  const tools = chatTools(rawTools);
  const hasTools = !!tools;
  const wantsStructured = wantsStructuredOutput(responsesBody.text);

  const body: Record<string, unknown> = { model, messages };
  if (tools) body.tools = tools;

  let injectedJSON = didInjectJSONInstruction;
  if (wantsStructured) {
    // Gemini rejects response_format json mode alongside tools, and rejects the
    // full strict schema; only request lightweight json_object on tool-free turns
    // and steer shape via a one-time prompt nudge.
    if (!hasTools) {
      body.response_format = { type: "json_object" };
    }
    if (!didInjectJSONInstruction) {
      messages.push({ role: "system", content: COACH_JSON_INSTRUCTION });
      injectedJSON = true;
    }
    body.messages = messages;
  }

  return {
    model,
    body,
    messages,
    wantsStructured,
    injectedJSON,
    consumedPending,
  };
}

export interface ChatReply {
  /** The Responses-shaped payload the iOS client parses. */
  responsesPayload: {
    id: string;
    output: ResponsesOutputItem[];
    usage: { input_tokens: number; output_tokens: number };
  };
  /** Assistant message to append to history for the next turn. */
  assistantMessage: ChatMessage;
  /** Raw tool_calls to re-emit before the next turn's tool results, if any. */
  pendingToolCalls: ChatMessage[];
  inputTokens: number;
  outputTokens: number;
  /** Plain assistant text, for the simpler web chat surface. */
  text: string;
}

/** Parse an OpenRouter chat-completions reply into Responses shape + history bits. */
export function parseChatCompletion(
  raw: Record<string, unknown>,
  fallbackId: string,
): ChatReply | null {
  const choices = raw.choices;
  if (!Array.isArray(choices) || choices.length === 0) return null;
  const message = (choices[0] as { message?: unknown }).message;
  if (!message || typeof message !== "object") return null;

  const id = typeof raw.id === "string" ? raw.id : fallbackId;
  const content = (message as { content?: unknown }).content;
  const text = typeof content === "string" ? content : "";

  const rawToolCalls = (message as { tool_calls?: unknown }).tool_calls;
  const toolCalls = Array.isArray(rawToolCalls) ? rawToolCalls : [];

  const output: ResponsesOutputItem[] = [];
  if (text) {
    output.push({
      type: "message",
      role: "assistant",
      content: [{ type: "output_text", text }],
    });
  }
  const pendingToolCalls: ChatMessage[] = [];
  for (const call of toolCalls) {
    const fn = (call as { function?: unknown }).function;
    if (!fn || typeof fn !== "object") continue;
    const name = (fn as { name?: unknown }).name;
    const args = (fn as { arguments?: unknown }).arguments;
    const callId = (call as { id?: unknown }).id;
    output.push({
      type: "function_call",
      name: typeof name === "string" ? name : "",
      call_id: typeof callId === "string" ? callId : "",
      arguments: typeof args === "string" ? args : "{}",
    });
    pendingToolCalls.push(call as ChatMessage);
  }

  const usageObj = (raw.usage ?? {}) as Record<string, unknown>;
  const inputTokens =
    (usageObj.prompt_tokens as number) ??
    (usageObj.input_tokens as number) ??
    0;
  const outputTokens =
    (usageObj.completion_tokens as number) ??
    (usageObj.output_tokens as number) ??
    0;

  // Assistant message recorded into history. When tools were requested we defer
  // emitting until the matching tool results arrive (handled via pendingToolCalls).
  const assistantMessage: ChatMessage =
    toolCalls.length > 0
      ? { role: "assistant", content: null, tool_calls: toolCalls }
      : { role: "assistant", content: text };

  return {
    responsesPayload: {
      id,
      output,
      usage: { input_tokens: inputTokens, output_tokens: outputTokens },
    },
    assistantMessage,
    pendingToolCalls,
    inputTokens,
    outputTokens,
    text,
  };
}

/** Build the OpenRouter request headers from the server-side key. */
export function openRouterHeaders(apiKey: string): HeadersInit {
  return {
    "Content-Type": "application/json",
    Authorization: `Bearer ${apiKey}`,
    "X-Title": "PulseLoop Web",
  };
}
