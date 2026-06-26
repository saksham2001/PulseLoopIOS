import { eq, sql } from "drizzle-orm";
import { db } from "@/db";
import {
  creditBalances,
  creditTransactions,
  type CreditTransaction,
} from "@/db/schema";

/**
 * Server-authoritative credit operations (roadmap C1/C2).
 *
 * The balance in `credit_balances` is the source of truth the iOS client syncs to.
 * Every mutation appends an immutable `credit_transactions` row so the running
 * balance and the ledger can never drift.
 *
 * NOTE: the app uses the Neon **HTTP** driver (`drizzle-orm/neon-http`), which does
 * not support interactive multi-statement transactions. We instead rely on a single
 * atomic `UPDATE ... RETURNING` for the balance and an idempotency unique constraint
 * (`credit_transactions_reference_uq`) so retried events (e.g. a re-sent purchase or
 * proxy request) cannot double-apply.
 */

/**
 * Temporary override: credits are unlimited for now. While true, the proxy routes
 * skip the pre-flight balance check (no 402) so AI features are never blocked.
 * Debits still run for accounting; flip back to `false` to re-enable enforcement.
 */
export const CREDITS_UNLIMITED = true;

export type CreditKind =
  // usage (debits) — mirror the iOS AIUsageKind
  | "coach_turn"
  | "summary"
  | "notification"
  | "daily_learning"
  | "subapp_generation"
  | "image_analysis"
  | "media_generation"
  | "other"
  // credits (grants)
  | "initial_grant"
  | "purchase"
  | "refund";

/** Read the current balance for a user, defaulting to 0 if no row exists yet. */
export async function getBalance(userId: string): Promise<number> {
  const rows = await db
    .select({ balance: creditBalances.balance })
    .from(creditBalances)
    .where(eq(creditBalances.userId, userId))
    .limit(1);
  return rows[0]?.balance ?? 0;
}

/** Ensure a balance row exists for the user (idempotent). */
async function ensureBalanceRow(userId: string): Promise<void> {
  await db
    .insert(creditBalances)
    .values({ userId, balance: 0 })
    .onConflictDoNothing({ target: creditBalances.userId });
}

export interface ApplyResult {
  applied: boolean; // false when deduped via referenceId
  balance: number;
  insufficient?: boolean; // true when a debit was refused for lack of credits
}

/**
 * Atomically apply a credit delta (negative = debit, positive = grant) and record a
 * ledger row. Returns the resulting balance.
 *
 * - When `referenceId` is provided and already recorded, this is a no-op that returns
 *   the current balance (`applied: false`) — safe to retry.
 * - For debits, when `allowOverdraft` is false (default) and the balance can't cover
 *   the cost, no change is made and `insufficient: true` is returned.
 */
export async function applyCredit(params: {
  userId: string;
  delta: number;
  kind: CreditKind;
  referenceId?: string | null;
  inputTokens?: number | null;
  outputTokens?: number | null;
  allowOverdraft?: boolean;
}): Promise<ApplyResult> {
  const {
    userId,
    delta,
    kind,
    referenceId = null,
    inputTokens = null,
    outputTokens = null,
    allowOverdraft = false,
  } = params;

  // Idempotency: if this external event was already recorded, do nothing.
  if (referenceId) {
    const existing = await db
      .select({ id: creditTransactions.id })
      .from(creditTransactions)
      .where(eq(creditTransactions.referenceId, referenceId))
      .limit(1);
    if (existing[0]) {
      return { applied: false, balance: await getBalance(userId) };
    }
  }

  await ensureBalanceRow(userId);

  // Atomic balance update. For debits without overdraft, the WHERE guard prevents
  // the update when funds are insufficient (concurrent-safe at the row level).
  const guard =
    delta < 0 && !allowOverdraft
      ? sql`and ${creditBalances.balance} + ${delta} >= 0`
      : sql``;

  const updated = await db
    .update(creditBalances)
    .set({
      balance: sql`${creditBalances.balance} + ${delta}`,
      updatedAt: new Date(),
    })
    .where(sql`${creditBalances.userId} = ${userId} ${guard}`)
    .returning({ balance: creditBalances.balance });

  if (!updated[0]) {
    // The guard blocked a debit → insufficient funds.
    return { applied: false, balance: await getBalance(userId), insufficient: true };
  }

  const balanceAfter = updated[0].balance;

  try {
    await db.insert(creditTransactions).values({
      userId,
      delta,
      balanceAfter,
      kind,
      inputTokens,
      outputTokens,
      referenceId,
    });
  } catch (err) {
    // A unique-violation here means a concurrent request recorded the same
    // referenceId first; roll the balance change back to keep the ledger truthful.
    await db
      .update(creditBalances)
      .set({ balance: sql`${creditBalances.balance} - ${delta}`, updatedAt: new Date() })
      .where(eq(creditBalances.userId, userId));
    if (referenceId) {
      return { applied: false, balance: await getBalance(userId) };
    }
    throw err;
  }

  return { applied: true, balance: balanceAfter };
}

/** Convenience debit for metered AI usage. */
export function debitUsage(params: {
  userId: string;
  cost: number;
  kind: CreditKind;
  referenceId?: string | null;
  inputTokens?: number | null;
  outputTokens?: number | null;
}): Promise<ApplyResult> {
  return applyCredit({
    userId: params.userId,
    delta: -Math.abs(params.cost),
    kind: params.kind,
    referenceId: params.referenceId,
    inputTokens: params.inputTokens,
    outputTokens: params.outputTokens,
  });
}

/** Convenience grant for initial credits / validated purchases / refunds. */
export function grantCredit(params: {
  userId: string;
  amount: number;
  kind: CreditKind;
  referenceId?: string | null;
}): Promise<ApplyResult> {
  return applyCredit({
    userId: params.userId,
    delta: Math.abs(params.amount),
    kind: params.kind,
    referenceId: params.referenceId,
    allowOverdraft: true,
  });
}

export type { CreditTransaction };

/**
 * Credits granted per StoreKit product id. MUST stay in sync with the iOS
 * `CreditStore.creditsByProductID`. The server is authoritative for grants, so this
 * map — not the client — decides how many credits a purchase is worth.
 */
export const CREDITS_BY_PRODUCT_ID: Record<string, number> = {
  "com.pulseloop.credits.100": 100,
  "com.pulseloop.credits.500": 500,
  "com.pulseloop.credits.1200": 1200,
};
