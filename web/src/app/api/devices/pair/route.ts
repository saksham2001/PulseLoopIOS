import { NextResponse } from "next/server";
import { db } from "@/db";
import { devices } from "@/db/schema";
import { getOrCreateCurrentUser } from "@/lib/auth";
import { generatePairingCode } from "@/lib/device";

const PAIRING_TTL_MS = 10 * 60 * 1000; // 10 minutes

/**
 * Signed-in user requests a pairing code to enter on their iOS device.
 * Creates a pending `devices` row holding the code until the device redeems it.
 */
export async function POST() {
  const user = await getOrCreateCurrentUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const code = generatePairingCode();
  const expiresAt = new Date(Date.now() + PAIRING_TTL_MS);

  const [device] = await db
    .insert(devices)
    .values({
      userId: user.id,
      pairingCode: code,
      pairingExpiresAt: expiresAt,
    })
    .returning();

  return NextResponse.json({
    code: device.pairingCode,
    expiresAt: expiresAt.toISOString(),
  });
}
