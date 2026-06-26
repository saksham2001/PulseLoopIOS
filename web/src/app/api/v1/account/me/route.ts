import { NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { db } from "@/db";
import { creditBalances, users } from "@/db/schema";
import { deviceFromRequest } from "@/lib/device";

/**
 * Device-authenticated "who am I linked to" lookup (roadmap E3).
 *
 * The iOS app pairs by entering a code generated inside a signed-in web (Clerk)
 * session, so the device token already resolves to a Clerk-backed account — but
 * the phone never learns *which* account. This endpoint closes that gap: it
 * returns the linked account's email + the device's own name/pairing time so the
 * app can confirm the link is correct and surface "Signed in as …" in Settings.
 *
 * Auth: `Authorization: Bearer <device token>`
 */
export async function GET(req: Request) {
  const device = await deviceFromRequest(req);
  if (!device) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const [owner] = await db
    .select({ email: users.email })
    .from(users)
    .where(eq(users.id, device.userId))
    .limit(1);

  const [balanceRow] = await db
    .select({ balance: creditBalances.balance })
    .from(creditBalances)
    .where(eq(creditBalances.userId, device.userId))
    .limit(1);

  return NextResponse.json({
    account: {
      email: owner?.email ?? null,
      creditBalance: balanceRow?.balance ?? 0,
    },
    device: {
      id: device.id,
      name: device.name,
      pairedAt: device.pairedAt,
      lastSeenAt: device.lastSeenAt,
    },
  });
}
