import { NextResponse } from "next/server";
import { getOrCreateCurrentUser } from "@/lib/auth";
import { getBalance, debitUsage, CREDITS_UNLIMITED } from "@/lib/credits";
import {
  OPENROUTER_CHAT_URL,
  DEFAULT_COACH_MODEL,
  openRouterHeaders,
} from "@/lib/openrouter";

/**
 * Web Coach chat turn (roadmap H1).
 *
 * Mirrors the iOS Coach proxy but authenticates via the **Clerk browser session**
 * instead of a device token, since the web surface is used by a signed-in user in a
 * browser, not the paired iPhone. It shares the same server-authoritative credit
 * ledger so a turn here debits the same balance, and uses the same provider the app
 * uses — **OpenRouter** (chat-completions) with the server-side `OPENROUTER_API_KEY`.
 *
 * Scope (MVP): text-only, single-shot reply. The on-device tool runtime + health DB
 * live on iOS; the web Coach is a grounded conversational surface on the shared
 * backend. Richer parity (tools, context packets) is layered in later H iterations.
 *
 * Security: the OpenRouter key never leaves the server; credits are checked before
 * the call and debited after.
 */

const COACH_TURN_COST = 1;
const MAX_HISTORY = 12;
const MAX_CHARS = 4000;

const SYSTEM_PROMPT = `You are PulseLoop, the user's all-in-one personal AI assistant. PulseLoop is a modular life-OS app — health and fitness is one part, but the user also relies on you for tasks, notes, journaling, planning, habits, mood, nutrition, finance, learning, and whatever custom modules they've installed. Think of yourself as a capable, friendly chief-of-staff for the user's whole life, not a narrow health bot.

Always respond directly and naturally to what the user actually said. Engage with their real words — their intent, tone, and topic. If they're casual, joking, venting, or off-topic, meet them there like a real assistant would. Never reply with a generic canned greeting that ignores their message.

You are running in the PulseLoop web app. You do NOT currently have direct access to the user's live ring/health data here (that lives in their iPhone app). If they ask about specific numbers like last night's heart rate or steps, be honest that the detailed data lives in the iOS app, offer to reason about what they tell you, and give genuinely useful general guidance. Keep replies concise, warm, and practical. Plain text only — no markdown headings or tables.`;

interface ChatTurn {
  role: "user" | "assistant";
  content: string;
}

function sanitizeHistory(input: unknown): ChatTurn[] {
  if (!Array.isArray(input)) return [];
  const out: ChatTurn[] = [];
  for (const raw of input) {
    if (!raw || typeof raw !== "object") continue;
    const role = (raw as { role?: unknown }).role;
    const content = (raw as { content?: unknown }).content;
    if ((role !== "user" && role !== "assistant") || typeof content !== "string") {
      continue;
    }
    const trimmed = content.trim().slice(0, MAX_CHARS);
    if (trimmed) out.push({ role, content: trimmed });
  }
  return out.slice(-MAX_HISTORY);
}

export async function POST(req: Request) {
  const user = await getOrCreateCurrentUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const apiKey = process.env.OPENROUTER_API_KEY;
  if (!apiKey) {
    return NextResponse.json({ error: "proxy_unconfigured" }, { status: 503 });
  }

  let payload: { message?: unknown; history?: unknown };
  try {
    payload = (await req.json()) as typeof payload;
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }

  const message =
    typeof payload.message === "string" ? payload.message.trim().slice(0, MAX_CHARS) : "";
  if (!message) {
    return NextResponse.json({ error: "empty_message" }, { status: 400 });
  }
  const history = sanitizeHistory(payload.history);

  // Enforce credits BEFORE spending the server's provider budget.
  const balanceBefore = await getBalance(user.id);
  if (!CREDITS_UNLIMITED && balanceBefore < COACH_TURN_COST) {
    return NextResponse.json(
      { error: "insufficient_credits", balance: balanceBefore },
      { status: 402 },
    );
  }

  const messages = [
    { role: "system", content: SYSTEM_PROMPT },
    ...history,
    { role: "user", content: message },
  ];

  let upstream: Response;
  try {
    upstream = await fetch(OPENROUTER_CHAT_URL, {
      method: "POST",
      headers: openRouterHeaders(apiKey),
      body: JSON.stringify({
        model: process.env.OPENROUTER_COACH_MODEL ?? DEFAULT_COACH_MODEL,
        messages,
      }),
    });
  } catch {
    return NextResponse.json({ error: "upstream_unreachable" }, { status: 502 });
  }

  const upstreamText = await upstream.text();
  if (!upstream.ok) {
    return NextResponse.json({ error: "upstream_error" }, { status: 502 });
  }

  let parsed: Record<string, unknown> = {};
  try {
    parsed = JSON.parse(upstreamText) as Record<string, unknown>;
  } catch {
    return NextResponse.json({ error: "bad_upstream" }, { status: 502 });
  }

  const reply = extractText(parsed);
  if (!reply) {
    return NextResponse.json({ error: "empty_reply" }, { status: 502 });
  }

  const usage = (parsed.usage ?? {}) as {
    prompt_tokens?: number;
    completion_tokens?: number;
  };
  const id = typeof parsed.id === "string" ? parsed.id : null;
  const result = await debitUsage({
    userId: user.id,
    cost: COACH_TURN_COST,
    kind: "coach_turn",
    referenceId: id ? `coach-web:${id}` : null,
    inputTokens: usage.prompt_tokens ?? null,
    outputTokens: usage.completion_tokens ?? null,
  });

  return NextResponse.json({ reply, balance: result.balance }, { status: 200 });
}

/** Pull the assistant text from an OpenRouter chat-completions reply. */
function extractText(parsed: Record<string, unknown>): string {
  const choices = parsed.choices;
  if (!Array.isArray(choices) || choices.length === 0) return "";
  const message = (choices[0] as { message?: unknown }).message;
  if (!message || typeof message !== "object") return "";
  const content = (message as { content?: unknown }).content;
  return typeof content === "string" ? content.trim() : "";
}
