import { randomBytes, randomInt } from "node:crypto";
import { eq } from "drizzle-orm";
import { db } from "@/db";
import { devices, type Device } from "@/db/schema";

/** Long-lived ingestion secret stored on the device after pairing. */
export function generateDeviceToken(): string {
  return "plk_" + randomBytes(32).toString("base64url");
}

/** Short, human-enterable pairing code (e.g. "4F9K2P"). */
export function generatePairingCode(): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no ambiguous chars
  let code = "";
  for (let i = 0; i < 6; i++) code += alphabet[randomInt(alphabet.length)];
  return code;
}

/**
 * Resolves a device from a `Authorization: Bearer <token>` header. Returns null
 * when the header is missing/malformed or the token is unknown. Used by the
 * ingest endpoint, which is intentionally outside Clerk session auth.
 */
export async function deviceFromRequest(req: Request): Promise<Device | null> {
  const header = req.headers.get("authorization") ?? "";
  const match = header.match(/^Bearer\s+(.+)$/i);
  if (!match) return null;
  const token = match[1].trim();
  if (!token) return null;

  const rows = await db
    .select()
    .from(devices)
    .where(eq(devices.token, token))
    .limit(1);
  return rows[0] ?? null;
}
