import { NextResponse } from "next/server";
import { and, desc, eq, gte } from "drizzle-orm";
import { db } from "@/db";
import { metricSamples } from "@/db/schema";
import { getOrCreateCurrentUser } from "@/lib/auth";

/**
 * Returns the signed-in user's metric samples, newest first. Optional query:
 *   ?kind=heart_rate  — filter to one metric kind
 *   ?days=7           — only samples from the last N days (default 30)
 *   ?limit=500        — cap rows (default 500, max 5000)
 */
export async function GET(req: Request) {
  const user = await getOrCreateCurrentUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const url = new URL(req.url);
  const kind = url.searchParams.get("kind");
  const days = Math.min(Math.max(Number(url.searchParams.get("days")) || 30, 1), 365);
  const limit = Math.min(Math.max(Number(url.searchParams.get("limit")) || 500, 1), 5000);
  const since = new Date(Date.now() - days * 24 * 60 * 60 * 1000);

  const conditions = [
    eq(metricSamples.userId, user.id),
    gte(metricSamples.recordedAt, since),
  ];
  if (kind) conditions.push(eq(metricSamples.kind, kind));

  const samples = await db
    .select({
      id: metricSamples.id,
      kind: metricSamples.kind,
      value: metricSamples.value,
      unit: metricSamples.unit,
      recordedAt: metricSamples.recordedAt,
    })
    .from(metricSamples)
    .where(and(...conditions))
    .orderBy(desc(metricSamples.recordedAt))
    .limit(limit);

  return NextResponse.json({ samples });
}
