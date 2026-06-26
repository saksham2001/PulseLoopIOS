import { NextResponse } from "next/server";
import { eq, sql } from "drizzle-orm";
import { db } from "@/db";
import { userSettings } from "@/db/schema";
import { getOrCreateCurrentUser } from "@/lib/auth";
import { normalizeWorkspace } from "@/lib/workspace";

/**
 * Clerk-session workspace settings (module enable/disable, Home feed layout,
 * theme, privacy permissions). One row per user; missing keys fall back to the
 * app defaults via `normalizeWorkspace`.
 */
export async function GET() {
  const user = await getOrCreateCurrentUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const [row] = await db
    .select()
    .from(userSettings)
    .where(eq(userSettings.userId, user.id))
    .limit(1);

  return NextResponse.json(
    normalizeWorkspace(
      row
        ? {
            modules: row.modules,
            homeLayout: row.homeLayout,
            theme: row.theme,
            permissions: row.permissions,
          }
        : null,
    ),
  );
}

/**
 * Partial update: any subset of { modules, homeLayout, theme, permissions }.
 * The merged-with-defaults result is returned so the client can adopt it.
 */
export async function PATCH(req: Request) {
  const user = await getOrCreateCurrentUser();
  if (!user) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  let body: {
    modules?: unknown;
    homeLayout?: unknown;
    theme?: unknown;
    permissions?: unknown;
  };
  try {
    body = await req.json();
  } catch {
    return NextResponse.json({ error: "invalid_json" }, { status: 400 });
  }

  const [existing] = await db
    .select()
    .from(userSettings)
    .where(eq(userSettings.userId, user.id))
    .limit(1);

  // Merge incoming keys onto whatever is stored, then normalize for storage.
  const merged = normalizeWorkspace({
    modules: body.modules ?? existing?.modules,
    homeLayout: body.homeLayout ?? existing?.homeLayout,
    theme: body.theme ?? existing?.theme,
    permissions: body.permissions ?? existing?.permissions,
  });

  await db
    .insert(userSettings)
    .values({
      userId: user.id,
      modules: merged.modules,
      homeLayout: merged.homeLayout,
      theme: merged.theme,
      permissions: merged.permissions,
      updatedAt: new Date(),
    })
    .onConflictDoUpdate({
      target: userSettings.userId,
      set: {
        modules: sql`excluded.modules`,
        homeLayout: sql`excluded.home_layout`,
        theme: sql`excluded.theme`,
        permissions: sql`excluded.permissions`,
        updatedAt: sql`excluded.updated_at`,
      },
    });

  return NextResponse.json(merged);
}
