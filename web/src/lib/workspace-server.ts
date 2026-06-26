import { eq } from "drizzle-orm";
import { db } from "@/db";
import { userSettings } from "@/db/schema";
import { getOrCreateCurrentUser } from "@/lib/auth";
import {
  DEFAULT_WORKSPACE,
  normalizeWorkspace,
  type WorkspaceSettings,
} from "@/lib/workspace";

/**
 * Server-side load of the signed-in user's workspace settings for SSR (so the
 * first paint already has the right theme + module visibility). Falls back to
 * defaults when signed out or no row exists yet.
 */
export async function loadWorkspaceSettings(): Promise<WorkspaceSettings> {
  const user = await getOrCreateCurrentUser();
  if (!user) return DEFAULT_WORKSPACE;

  const [row] = await db
    .select()
    .from(userSettings)
    .where(eq(userSettings.userId, user.id))
    .limit(1);

  return normalizeWorkspace(
    row
      ? {
          modules: row.modules,
          homeLayout: row.homeLayout,
          theme: row.theme,
          permissions: row.permissions,
        }
      : null,
  );
}
