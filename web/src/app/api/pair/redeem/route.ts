import { NextResponse } from "next/server";
import { and, eq, gt, isNull } from "drizzle-orm";
import { db } from "@/db";
import { devices } from "@/db/schema";
import { generateDeviceToken } from "@/lib/device";

/**
 * Device-side pairing. The iOS app posts the 6-char code the user generated on
 * web; if it's valid and unexpired, we mint a long-lived ingestion token and
 * return it. Public route (the device has no Clerk session yet).
 *
 * Body: { "code": "4F9K2P", "deviceName": "iPhone 16 Pro" }
 */
export async function POST(req: Request) {
  let body: { code?: string; deviceName?: string };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }

  const code = body.code?.trim().toUpperCase();
  if (!code) {
    return NextResponse.json({ error: "missing_code" }, { status: 400 });
  }

  const rows = await db
    .select()
    .from(devices)
    .where(
      and(
        eq(devices.pairingCode, code),
        isNull(devices.token),
        gt(devices.pairingExpiresAt, new Date()),
      ),
    )
    .limit(1);

  const pending = rows[0];
  if (!pending) {
    return NextResponse.json(
      { error: "invalid_or_expired_code" },
      { status: 404 },
    );
  }

  const token = generateDeviceToken();
  const [paired] = await db
    .update(devices)
    .set({
      token,
      pairingCode: null,
      pairingExpiresAt: null,
      pairedAt: new Date(),
      lastSeenAt: new Date(),
      name: body.deviceName?.slice(0, 60) || pending.name,
    })
    .where(eq(devices.id, pending.id))
    .returning();

  return NextResponse.json({
    token,
    deviceId: paired.id,
    name: paired.name,
  });
}
