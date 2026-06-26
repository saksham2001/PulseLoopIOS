import { randomUUID } from "node:crypto";
import { eq, lt } from "drizzle-orm";
import { db } from "@/db";
import { coachSessions } from "@/db/schema";
import type { ChatMessage } from "./openrouter";

/**
 * Persistence for the OpenRouter Coach proxy's conversation state. OpenRouter is
 * stateless, but the iOS orchestrator resumes a multi-round tool loop via
 * `previous_response_id`; we store the running chat history here keyed on the
 * response id we return, and resume it on the next turn.
 */

export interface CoachSessionState {
  messages: ChatMessage[];
  pendingToolCalls: ChatMessage[];
  injectedJSON: boolean;
}

const EMPTY: CoachSessionState = {
  messages: [],
  pendingToolCalls: [],
  injectedJSON: false,
};

/** Load prior state for a `previous_response_id`, or empty when absent/foreign. */
export async function loadCoachSession(
  userId: string,
  previousResponseId: unknown,
): Promise<CoachSessionState> {
  if (typeof previousResponseId !== "string" || !previousResponseId) {
    return { ...EMPTY };
  }
  const rows = await db
    .select()
    .from(coachSessions)
    .where(eq(coachSessions.responseId, previousResponseId))
    .limit(1);
  const row = rows[0];
  if (!row || row.userId !== userId) return { ...EMPTY };

  try {
    return {
      messages: JSON.parse(row.messages) as ChatMessage[],
      pendingToolCalls: JSON.parse(row.pendingToolCalls) as ChatMessage[],
      injectedJSON: row.injectedJson === 1,
    };
  } catch {
    return { ...EMPTY };
  }
}

/** Persist state under a fresh response id and return it. */
export async function saveCoachSession(
  userId: string,
  state: CoachSessionState,
): Promise<string> {
  const responseId = `resp_${randomUUID()}`;
  await db.insert(coachSessions).values({
    responseId,
    userId,
    messages: JSON.stringify(state.messages),
    pendingToolCalls: JSON.stringify(state.pendingToolCalls),
    injectedJson: state.injectedJSON ? 1 : 0,
  });
  return responseId;
}

/** Best-effort prune of sessions older than `maxAgeMs` (default 24h). */
export async function pruneCoachSessions(maxAgeMs = 24 * 60 * 60 * 1000): Promise<void> {
  const cutoff = new Date(Date.now() - maxAgeMs);
  try {
    await db.delete(coachSessions).where(lt(coachSessions.updatedAt, cutoff));
  } catch {
    // Pruning is non-critical; ignore failures.
  }
}
