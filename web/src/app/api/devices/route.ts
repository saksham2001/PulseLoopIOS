import { NextResponse } from "next/server";
import { and, desc, eq, isNotNull } from "drizzle-orm";
import { db } from "@/db";
import { devices } from "@/db/schema";
import { getOrCreateCurrentUser } from "@/lib/auth";

/**
 * Lists the signed-in user's *paired* devices (those that completed pairing and
 * hold an ingestion token). Used by the dashboard to reflect pairing state live:
 * the web client polls this after showing a code so the UI flips to "connected"
 * as soon as the iOS app redeems it — without a manual refresh.
 *
 * Never returns the device token (secret); only safe metadata.
 */
export async function GET() {
  const user = await getOrCreateCurrentUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const rows = await db
    .select({
      id: devices.id,
      name: devices.name,
      pairedAt: devices.pairedAt,
      lastSeenAt: devices.lastSeenAt,
    })
    .from(devices)
    .where(and(eq(devices.userId, user.id), isNotNull(devices.token)))
    .orderBy(desc(devices.pairedAt));

  return NextResponse.json({
    devices: rows.map((d) => ({
      id: d.id,
      name: d.name,
      pairedAt: d.pairedAt?.toISOString() ?? null,
      lastSeenAt: d.lastSeenAt?.toISOString() ?? null,
    })),
  });
}
