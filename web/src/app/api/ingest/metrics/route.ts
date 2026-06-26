import { NextResponse } from "next/server";
import { eq, sql } from "drizzle-orm";
import { db } from "@/db";
import { devices, metricSamples } from "@/db/schema";
import { deviceFromRequest } from "@/lib/device";

interface IncomingSample {
  clientId?: string;
  kind?: string;
  value?: number;
  unit?: string | null;
  recordedAt?: string;
}

const MAX_BATCH = 1000;

/**
 * Device-authenticated metric upload. Idempotent: re-sending the same
 * `clientId` updates the existing row instead of duplicating, so the iOS app
 * can safely retry.
 *
 * Auth: `Authorization: Bearer <device token>`
 * Body: { "samples": [{ clientId, kind, value, unit, recordedAt }] }
 */
export async function POST(req: Request) {
  const device = await deviceFromRequest(req);
  if (!device) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  let body: { samples?: IncomingSample[] };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }

  const samples = body.samples ?? [];
  if (!Array.isArray(samples) || samples.length === 0) {
    return NextResponse.json({ error: "no_samples" }, { status: 400 });
  }
  if (samples.length > MAX_BATCH) {
    return NextResponse.json(
      { error: "batch_too_large", max: MAX_BATCH },
      { status: 413 },
    );
  }

  const rows = [];
  for (const s of samples) {
    if (
      !s.clientId ||
      !s.kind ||
      typeof s.value !== "number" ||
      !Number.isFinite(s.value) ||
      !s.recordedAt
    ) {
      continue;
    }
    const recordedAt = new Date(s.recordedAt);
    if (Number.isNaN(recordedAt.getTime())) continue;

    rows.push({
      userId: device.userId,
      deviceId: device.id,
      kind: s.kind.slice(0, 64),
      value: s.value,
      unit: s.unit?.slice(0, 32) ?? null,
      recordedAt,
      clientId: s.clientId.slice(0, 128),
    });
  }

  if (rows.length === 0) {
    return NextResponse.json({ error: "no_valid_samples" }, { status: 400 });
  }

  await db
    .insert(metricSamples)
    .values(rows)
    .onConflictDoUpdate({
      target: [metricSamples.userId, metricSamples.clientId],
      set: {
        value: sql`excluded.value`,
        kind: sql`excluded.kind`,
        unit: sql`excluded.unit`,
        recordedAt: sql`excluded.recorded_at`,
      },
    });

  await db
    .update(devices)
    .set({ lastSeenAt: new Date() })
    .where(eq(devices.id, device.id));

  return NextResponse.json({ accepted: rows.length });
}
