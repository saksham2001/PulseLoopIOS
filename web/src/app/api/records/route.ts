import { NextResponse } from "next/server";
import { and, desc, eq, sql } from "drizzle-orm";
import { db } from "@/db";
import { syncedRecords } from "@/db/schema";
import { getOrCreateCurrentUser } from "@/lib/auth";

/**
 * Clerk-session CRUD for the signed-in user's generic records (Tasks, Notes,
 * Protocol, Journal, Meals, Mood, …) in `synced_records`. This is the web's
 * write path; the iOS device write path is `/api/v1/sync/records` (Bearer token).
 * Both target the same `(userId, type, clientId)` rows, so a web edit and a
 * phone edit reconcile via last-writer-wins on `updatedAt`.
 *
 *   GET    ?type=<t>&limit=<n>   → live (non-deleted) records of one type
 *   POST   { type, clientId?, payload }   → upsert one record (returns it)
 *   DELETE ?type=<t>&clientId=<c>         → soft-delete (tombstone)
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

  const records = await db
    .select({
      clientId: syncedRecords.clientId,
      type: syncedRecords.type,
      payload: syncedRecords.payload,
      updatedAt: syncedRecords.updatedAt,
    })
    .from(syncedRecords)
    .where(
      and(
        eq(syncedRecords.userId, user.id),
        eq(syncedRecords.type, type),
        eq(syncedRecords.deleted, false),
      ),
    )
    .orderBy(desc(syncedRecords.updatedAt))
    .limit(limit);

  return NextResponse.json({ records });
}

export async function POST(req: Request) {
  const user = await getOrCreateCurrentUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  let body: { type?: string; clientId?: string; payload?: unknown };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }

  if (!body.type || body.payload === undefined || body.payload === null) {
    return NextResponse.json({ error: "missing_fields" }, { status: 400 });
  }

  const type = body.type.slice(0, 64);
  const clientId = (body.clientId || crypto.randomUUID()).slice(0, 128);
  const updatedAt = new Date();

  await db
    .insert(syncedRecords)
    .values({
      userId: user.id,
      type,
      clientId,
      payload: body.payload,
      updatedAt,
      deleted: false,
    })
    .onConflictDoUpdate({
      target: [syncedRecords.userId, syncedRecords.type, syncedRecords.clientId],
      set: {
        payload: sql`excluded.payload`,
        updatedAt: sql`excluded.updated_at`,
        deleted: false,
      },
    });

  return NextResponse.json({
    clientId,
    type,
    payload: body.payload,
    updatedAt: updatedAt.toISOString(),
  });
}

export async function DELETE(req: Request) {
  const user = await getOrCreateCurrentUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const url = new URL(req.url);
  const type = url.searchParams.get("type");
  const clientId = url.searchParams.get("clientId");
  if (!type || !clientId) {
    return NextResponse.json({ error: "missing_fields" }, { status: 400 });
  }

  await db
    .update(syncedRecords)
    .set({ deleted: true, updatedAt: new Date() })
    .where(
      and(
        eq(syncedRecords.userId, user.id),
        eq(syncedRecords.type, type),
        eq(syncedRecords.clientId, clientId),
      ),
    );

  return NextResponse.json({ ok: true });
}
