import { NextResponse } from "next/server";
import { and, desc, eq, gt, sql } from "drizzle-orm";
import { db } from "@/db";
import { devices, syncedRecords } from "@/db/schema";
import { deviceFromRequest } from "@/lib/device";
import { getOrCreateCurrentUser } from "@/lib/auth";

interface IncomingRecord {
  type?: string;
  clientId?: string;
  payload?: unknown;
  updatedAt?: string;
  deleted?: boolean;
}

const MAX_BATCH = 1000;

/**
 * Device-authenticated generic record sync (Tasks, Notes, …). Idempotent and
 * last-writer-wins: re-sending the same `(type, clientId)` upserts the row, and
 * an incoming write only overwrites when its `updatedAt` is newer-or-equal, so
 * the phone can safely retry and stale retries can't clobber fresher state.
 *
 * Auth: `Authorization: Bearer <device token>`
 * Body: { "records": [{ type, clientId, payload, updatedAt, deleted? }] }
 */
export async function POST(req: Request) {
  const device = await deviceFromRequest(req);
  if (!device) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  let body: { records?: IncomingRecord[] };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }

  const records = body.records ?? [];
  if (!Array.isArray(records) || records.length === 0) {
    return NextResponse.json({ error: "no_records" }, { status: 400 });
  }
  if (records.length > MAX_BATCH) {
    return NextResponse.json(
      { error: "batch_too_large", max: MAX_BATCH },
      { status: 413 },
    );
  }

  const rows = [];
  for (const r of records) {
    if (
      !r.type ||
      !r.clientId ||
      r.payload === undefined ||
      r.payload === null ||
      !r.updatedAt
    ) {
      continue;
    }
    const updatedAt = new Date(r.updatedAt);
    if (Number.isNaN(updatedAt.getTime())) continue;

    rows.push({
      userId: device.userId,
      deviceId: device.id,
      type: r.type.slice(0, 64),
      clientId: r.clientId.slice(0, 128),
      payload: r.payload,
      updatedAt,
      deleted: r.deleted === true,
    });
  }

  if (rows.length === 0) {
    return NextResponse.json({ error: "no_valid_records" }, { status: 400 });
  }

  await db
    .insert(syncedRecords)
    .values(rows)
    .onConflictDoUpdate({
      target: [syncedRecords.userId, syncedRecords.type, syncedRecords.clientId],
      set: {
        payload: sql`excluded.payload`,
        updatedAt: sql`excluded.updated_at`,
        deleted: sql`excluded.deleted`,
        deviceId: sql`excluded.device_id`,
      },
      // Last-writer-wins: only apply when the incoming row is newer-or-equal.
      setWhere: sql`excluded.updated_at >= ${syncedRecords.updatedAt}`,
    });

  await db
    .update(devices)
    .set({ lastSeenAt: new Date() })
    .where(eq(devices.id, device.id));

  return NextResponse.json({ accepted: rows.length });
}

/**
 * Clerk-session read of the signed-in user's synced records of one `type`,
 * newest-modified first. Tombstoned (deleted) rows are excluded by default so
 * web surfaces render the live set.
 *
 *   ?type=task        — required; the record type to read
 *   ?since=<iso>      — only records modified strictly after this cursor
 *   ?limit=500        — cap rows (default 500, max 5000)
 *   ?includeDeleted=1 — include tombstones (for client reconciliation)
 */
export async function GET(req: Request) {
  const user = await getOrCreateCurrentUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const url = new URL(req.url);
  const type = url.searchParams.get("type");
  if (!type) {
    return NextResponse.json({ error: "missing_type" }, { status: 400 });
  }
  const limit = Math.min(
    Math.max(Number(url.searchParams.get("limit")) || 500, 1),
    5000,
  );
  const includeDeleted = url.searchParams.get("includeDeleted") === "1";

  const conditions = [
    eq(syncedRecords.userId, user.id),
    eq(syncedRecords.type, type),
  ];
  const sinceParam = url.searchParams.get("since");
  if (sinceParam) {
    const since = new Date(sinceParam);
    if (!Number.isNaN(since.getTime())) {
      conditions.push(gt(syncedRecords.updatedAt, since));
    }
  }
  if (!includeDeleted) {
    conditions.push(eq(syncedRecords.deleted, false));
  }

  const records = await db
    .select({
      clientId: syncedRecords.clientId,
      type: syncedRecords.type,
      payload: syncedRecords.payload,
      updatedAt: syncedRecords.updatedAt,
      deleted: syncedRecords.deleted,
    })
    .from(syncedRecords)
    .where(and(...conditions))
    .orderBy(desc(syncedRecords.updatedAt))
    .limit(limit);

  return NextResponse.json({ records });
}
