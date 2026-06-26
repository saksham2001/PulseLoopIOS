import { NextResponse } from "next/server";
import { deviceFromRequest } from "@/lib/device";
import { verifyTransaction } from "@/lib/appstore";
import { grantCredit, getBalance, CREDITS_BY_PRODUCT_ID } from "@/lib/credits";

/**
 * App Store purchase validation + server-side credit grant (roadmap D2).
 *
 * The app sends the signed JWS transaction it received from StoreKit. The server
 * verifies it with Apple (so a tampered client can't forge a grant), maps the product
 * id → credits, and grants them to the server-authoritative ledger — idempotent on the
 * Apple transaction id so a replay/retry can't double-grant.
 *
 * - `POST /api/v1/credits/validate`
 * - `Authorization: Bearer <device token>`
 * - Body: `{ "signedTransaction": "<JWS>" }`
 * - On success: `{ "granted": number, "balance": number }` (authoritative balance).
 *
 * Returns `503` when verification isn't configured (see `lib/appstore.ts`) so credits
 * are never granted on unverified data.
 */
export async function POST(req: Request) {
  const device = await deviceFromRequest(req);
  if (!device) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  let body: { signedTransaction?: string };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }

  const signed = body.signedTransaction?.trim();
  if (!signed) {
    return NextResponse.json({ error: "missing_transaction" }, { status: 400 });
  }

  const verification = await verifyTransaction(signed);
  if (!verification.ok) {
    if (verification.reason === "unconfigured") {
      return NextResponse.json({ error: "validation_unconfigured" }, { status: 503 });
    }
    return NextResponse.json({ error: "invalid_transaction" }, { status: 400 });
  }

  const { productId, transactionId } = verification.transaction;
  const credits = CREDITS_BY_PRODUCT_ID[productId];
  if (!credits) {
    return NextResponse.json({ error: "unknown_product" }, { status: 400 });
  }

  // Idempotent on the Apple transaction id: a replay returns the current balance
  // without granting again.
  const result = await grantCredit({
    userId: device.userId,
    amount: credits,
    kind: "purchase",
    referenceId: `appstore:${transactionId}`,
  });

  return NextResponse.json({
    granted: result.applied ? credits : 0,
    balance: result.applied ? result.balance : await getBalance(device.userId),
  });
}
