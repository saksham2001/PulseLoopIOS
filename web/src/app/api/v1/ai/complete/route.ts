import { NextResponse } from "next/server";
import { deviceFromRequest } from "@/lib/device";
import { getBalance, debitUsage, type CreditKind, CREDITS_UNLIMITED } from "@/lib/credits";
import { OPENROUTER_CHAT_URL, openRouterHeaders } from "@/lib/openrouter";

/**
 * Generic AI proxy for the iOS app (roadmap: server-held key).
 *
 * The phone authenticates with its paired **device token** and sends an
 * OpenRouter chat-completions–shaped body (`{ model, messages, temperature,
 * max_tokens, response_format?, ... }`). Multimodal content is supported: a
 * message `content` may be a string OR an array of parts
 * (`{type:"text"|"image_url", ...}`), so vision / label scans work through the
 * proxy exactly like a direct OpenRouter call.
 *
 * Why: the OpenRouter API key lives ONLY in `process.env.OPENROUTER_API_KEY` on
 * the server and is never shipped to the device. The app calls this endpoint
 * instead of OpenRouter directly. We meter a flat credit per call (token usage
 * recorded for accounting) against the shared, server-authoritative ledger.
 *
 * The upstream OpenRouter JSON is returned verbatim so the iOS `AIService`
 * decoders work unchanged.
 */

const MAX_BODY_BYTES = 12 * 1024 * 1024; // generous: base64 images
const ALLOWED_KEYS = new Set([
  "model",
  "messages",
  "temperature",
  "max_tokens",
  "top_p",
  "response_format",
  "stop",
]);

/** Map an optional client-declared usage kind to a credit kind + flat cost.
 * The iOS `AIUsageKind` rawValues are camelCase; map them to the ledger kinds. */
function costFor(kind: unknown): { kind: CreditKind; cost: number } {
  switch (kind) {
    case "imageAnalysis":
    case "image_analysis":
      return { kind: "image_analysis", cost: 1 };
    case "summary":
      return { kind: "summary", cost: 1 };
    case "dailyLearning":
    case "daily_learning":
      return { kind: "daily_learning", cost: 1 };
    case "subAppGeneration":
    case "subapp_generation":
      return { kind: "subapp_generation", cost: 1 };
    case "mediaGeneration":
    case "media_generation":
      return { kind: "media_generation", cost: 1 };
    case "coachTurn":
    case "coach_turn":
      return { kind: "coach_turn", cost: 1 };
    default:
      return { kind: "other", cost: 1 };
  }
}

export async function POST(req: Request) {
  const device = await deviceFromRequest(req);
  if (!device) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const apiKey = process.env.OPENROUTER_API_KEY;
  if (!apiKey) {
    return NextResponse.json({ error: "proxy_unconfigured" }, { status: 503 });
  }

  const raw = await req.text();
  if (raw.length > MAX_BODY_BYTES) {
    return NextResponse.json({ error: "payload_too_large" }, { status: 413 });
  }

  let payload: Record<string, unknown>;
  try {
    payload = JSON.parse(raw) as Record<string, unknown>;
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }

  const model = payload.model;
  const messages = payload.messages;
  if (typeof model !== "string" || !model) {
    return NextResponse.json({ error: "missing_model" }, { status: 400 });
  }
  if (!Array.isArray(messages) || messages.length === 0) {
    return NextResponse.json({ error: "missing_messages" }, { status: 400 });
  }

  // Whitelist only the fields we forward — never let a client set, e.g.,
  // streaming or provider routing through the proxy.
  const forward: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(payload)) {
    if (ALLOWED_KEYS.has(k)) forward[k] = v;
  }

  const { kind, cost } = costFor(payload.usage_kind);

  const balanceBefore = await getBalance(device.userId);
  if (!CREDITS_UNLIMITED && balanceBefore < cost) {
    return NextResponse.json(
      { error: "insufficient_credits", balance: balanceBefore },
      { status: 402 },
    );
  }

  let upstream: Response;
  try {
    upstream = await fetch(OPENROUTER_CHAT_URL, {
      method: "POST",
      headers: openRouterHeaders(apiKey),
      body: JSON.stringify(forward),
    });
  } catch {
    return NextResponse.json({ error: "upstream_unreachable" }, { status: 502 });
  }

  const upstreamText = await upstream.text();
  if (!upstream.ok) {
    return NextResponse.json(
      { error: "upstream_error", status: upstream.status },
      { status: 502 },
    );
  }

  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(upstreamText) as Record<string, unknown>;
  } catch {
    return NextResponse.json({ error: "bad_upstream" }, { status: 502 });
  }

  const usage = (parsed.usage ?? {}) as {
    prompt_tokens?: number;
    completion_tokens?: number;
  };
  const id = typeof parsed.id === "string" ? parsed.id : null;
  await debitUsage({
    userId: device.userId,
    cost,
    kind,
    referenceId: id ? `ai-proxy:${id}` : null,
    inputTokens: usage.prompt_tokens ?? null,
    outputTokens: usage.completion_tokens ?? null,
  });

  // Return the upstream payload verbatim so the iOS decoders are unchanged.
  return NextResponse.json(parsed, { status: 200 });
}
