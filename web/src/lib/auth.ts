import { auth, currentUser } from "@clerk/nextjs/server";
import { eq } from "drizzle-orm";
import { db } from "@/db";
import { users, type User } from "@/db/schema";

/**
 * Resolves the signed-in Clerk user to a row in our `users` table, creating it
 * on first sight. Returns null when there is no active session.
 */
export async function getOrCreateCurrentUser(): Promise<User | null> {
  const { userId } = await auth();
  if (!userId) return null;

  const existing = await db
    .select()
    .from(users)
    .where(eq(users.clerkId, userId))
    .limit(1);
  if (existing[0]) return existing[0];

  const clerk = await currentUser();
  const email = clerk?.primaryEmailAddress?.emailAddress ?? null;

  const [created] = await db
    .insert(users)
    .values({ clerkId: userId, email })
    .onConflictDoUpdate({ target: users.clerkId, set: { email } })
    .returning();

  return created;
}
