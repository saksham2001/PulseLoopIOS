import { NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { db } from "@/db";
import { devices } from "@/db/schema";
import { deviceFromRequest } from "@/lib/device";
import { getBalance, debitUsage, CREDITS_UNLIMITED } from "@/lib/credits";
import {
  OPENROUTER_CHAT_URL,
  openRouterHeaders,
  buildChatRequest,
  parseChatCompletion,
} from "@/lib/openrouter";
import {
  loadCoachSession,
  saveCoachSession,
  pruneCoachSessions,
} from "@/lib/coach-session";

/**
 * AI proxy for the iOS Coach (roadmap C2). The app's `BackendProxyResponsesClient`
 * sends the verbatim OpenAI **Responses**-shaped body the orchestrator builds and
 * expects a Responses-shaped reply back. We provider through **OpenRouter** (the
 * same provider the app uses directly), so the server translates Responses ⇄
 * OpenRouter chat-completions and keeps the multi-round conversation state.
 *
 * - `POST /api/v1/coach/responses`
 * - `Authorization: Bearer <device token>` — the PulseLoop "session" credential the
 *   app holds after pairing. NOT a provider key; the server attaches its own.
 * - Body: the verbatim Responses request `{model, input, tools, text, previous_response_id}`.
 * - On success: a Responses-shaped JSON (`{id, output, usage}`) augmented with a
 *   top-level `pulseloop_credits: { balance }` the client trusts as authoritative.
 *   The returned `id` resumes the conversation on the next turn's `previous_response_id`.
 * - `402 Payment Required` when the user is out of credits (checked before forwarding).
 *
 * Security: the OpenRouter key lives only in `process.env.OPENROUTER_API_KEY`
 * (server side); credits are debited from the server-authoritative ledger so a
 * client cannot bypass metering.
 */

// Flat per-call cost, mirroring the iOS AIUsageKind.coachTurn baseCost.
const COACH_TURN_COST = 1;

export async function POST(req: Request) {
  const device = await deviceFromRequest(req);
  if (!device) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const apiKey = process.env.OPENROUTER_API_KEY;
  if (!apiKey) {
    return NextResponse.json({ error: "proxy_unconfigured" }, { status: 503 });
  }

  let responsesBody: Record<string, unknown>;
  try {
    responsesBody = (await req.json()) as Record<string, unknown>;
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }

  // Enforce credits BEFORE spending the server's provider budget.
  const balanceBefore = await getBalance(device.userId);
  if (!CREDITS_UNLIMITED && balanceBefore < COACH_TURN_COST) {
    return NextResponse.json(
      {
        error: "insufficient_credits",
        pulseloop_credits: { balance: balanceBefore },
      },
      { status: 402 },
    );
  }

  // Resume prior conversation state (OpenRouter is stateless).
  const prior = await loadCoachSession(
    device.userId,
    responsesBody.previous_response_id,
  );
  const translated = buildChatRequest(
    responsesBody,
    prior.messages,
    prior.pendingToolCalls,
    prior.injectedJSON,
  );

  // Forward to OpenRouter with the server's key.
  let upstream: Response;
  try {
    upstream = await fetch(OPENROUTER_CHAT_URL, {
      method: "POST",
      headers: openRouterHeaders(apiKey),
      body: JSON.stringify(translated.body),
    });
  } catch {
    return NextResponse.json({ error: "upstream_unreachable" }, { status: 502 });
  }

  const upstreamText = await upstream.text();
  if (!upstream.ok) {
    return new NextResponse(upstreamText || "{}", {
      status: upstream.status,
      headers: { "Content-Type": "application/json" },
    });
  }

  let parsedUpstream: Record<string, unknown>;
  try {
    parsedUpstream = JSON.parse(upstreamText) as Record<string, unknown>;
  } catch {
    return NextResponse.json({ error: "bad_upstream" }, { status: 502 });
  }

  const reply = parseChatCompletion(parsedUpstream, "resp_pending");
  if (!reply) {
    return NextResponse.json({ error: "empty_reply" }, { status: 502 });
  }

  // Persist updated conversation state and mint the response id the client will
  // send back as `previous_response_id` next turn.
  const nextMessages = [...translated.messages, reply.assistantMessage];
  const responseId = await saveCoachSession(device.userId, {
    messages: nextMessages,
    pendingToolCalls: reply.pendingToolCalls,
    injectedJSON: translated.injectedJSON,
  });
  void pruneCoachSessions();

  // Debit AFTER a successful call, recording real token usage. Idempotency is keyed
  // on the minted response id so a client retry of the same response can't double-charge.
  const result = await debitUsage({
    userId: device.userId,
    cost: COACH_TURN_COST,
    kind: "coach_turn",
    referenceId: `coach:${responseId}`,
    inputTokens: reply.inputTokens || null,
    outputTokens: reply.outputTokens || null,
  });

  await db
    .update(devices)
    .set({ lastSeenAt: new Date() })
    .where(eq(devices.id, device.id));

  // Responses-shaped payload + authoritative balance.
  const payload = {
    ...reply.responsesPayload,
    id: responseId,
    pulseloop_credits: { balance: result.balance },
  };
  return NextResponse.json(payload, { status: 200 });
}
