import { NextResponse } from "next/server";
import { eq } from "drizzle-orm";
import { db } from "@/db";
import {
  creditBalances,
  creditTransactions,
  devices,
  metricSamples,
} from "@/db/schema";
import { deviceFromRequest } from "@/lib/device";

/**
 * Device-authenticated deletion (GDPR "right to erasure").
 *
 * Two scopes:
 *   - `"device"` (default): unpair only this device. Its token is cleared so it
 *     can no longer ingest; the user's data and other devices are untouched.
 *   - `"account"`: erase all server-side data for the owner — metric samples,
 *     credit balance + ledger, and every paired device row.
 *
 * Auth: `Authorization: Bearer <device token>`
 * Body: { "scope": "device" | "account" }  (optional, defaults to "device")
 */
export async function POST(req: Request) {
  const device = await deviceFromRequest(req);
  if (!device) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  let scope: "device" | "account" = "device";
  try {
    const body = (await req.json()) as { scope?: unknown };
    if (body?.scope === "account") scope = "account";
  } catch {
    // No/empty body → default device scope.
  }

  if (scope === "account") {
    const userId = device.userId;
    // Order matters only for clarity; FKs cascade from users, but we delete the
    // owned rows directly so the user row (Clerk identity) can survive.
    await db.delete(metricSamples).where(eq(metricSamples.userId, userId));
    await db.delete(creditTransactions).where(eq(creditTransactions.userId, userId));
    await db.delete(creditBalances).where(eq(creditBalances.userId, userId));
    await db.delete(devices).where(eq(devices.userId, userId));
    return NextResponse.json({ deleted: "account" });
  }

  // Device scope: revoke this device's token so it can no longer ingest. We keep
  // the row (with token nulled) so paired-device history on web stays coherent.
  await db
    .update(devices)
    .set({ token: null })
    .where(eq(devices.id, device.id));
  return NextResponse.json({ deleted: "device" });
}
