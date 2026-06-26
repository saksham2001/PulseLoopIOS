/**
 * One-off end-to-end verification of the device sync pipeline WITHOUT a browser.
 * Seeds a user + pairing code directly (simulating the web "generate code"
 * action), then exercises the real HTTP endpoints exactly as the iOS app does:
 *   redeem code -> get token -> ingest samples -> (verify row count in DB).
 *
 * Run: node --env-file=.env.local scripts/e2e-check.mjs
 */
import { neon } from "@neondatabase/serverless";

const BASE = process.env.E2E_BASE_URL || "http://localhost:3000";
const sql = neon(process.env.DATABASE_URL);

const clerkId = "e2e_" + Math.random().toString(36).slice(2, 10);
const code = "E2E" + Math.random().toString(36).slice(2, 5).toUpperCase();

function assert(cond, msg) {
  if (!cond) {
    console.error("FAIL:", msg);
    process.exit(1);
  }
  console.log("ok  -", msg);
}

const [user] = await sql`
  insert into users (clerk_id, email) values (${clerkId}, ${clerkId + "@test.dev"})
  returning id`;
await sql`
  insert into devices (user_id, pairing_code, pairing_expires_at)
  values (${user.id}, ${code}, ${new Date(Date.now() + 600000).toISOString()})`;
console.log("seeded user + pairing code", code);

// 1. Redeem (device side)
const redeem = await fetch(`${BASE}/api/pair/redeem`, {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({ code, deviceName: "E2E iPhone" }),
});
assert(redeem.ok, `redeem returned ${redeem.status}`);
const { token } = await redeem.json();
assert(typeof token === "string" && token.startsWith("plk_"), "got device token");

// 2. Ingest samples (device side)
const now = Date.now();
const samples = Array.from({ length: 5 }, (_, i) => ({
  clientId: `${clerkId}-hr-${i}`,
  kind: "heart_rate",
  value: 60 + i,
  unit: "bpm",
  recordedAt: new Date(now - i * 3600_000).toISOString(),
}));
const ingest = await fetch(`${BASE}/api/ingest/metrics`, {
  method: "POST",
  headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
  body: JSON.stringify({ samples }),
});
assert(ingest.ok, `ingest returned ${ingest.status}`);
const ingestBody = await ingest.json();
assert(ingestBody.accepted === 5, `accepted 5 samples (got ${ingestBody.accepted})`);

// 3. Idempotency: re-send same batch -> still 5, no duplicates
await fetch(`${BASE}/api/ingest/metrics`, {
  method: "POST",
  headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
  body: JSON.stringify({ samples }),
});
const rows = await sql`
  select count(*)::int as n from metric_samples where user_id = ${user.id}`;
assert(rows[0].n === 5, `idempotent upsert kept 5 rows (got ${rows[0].n})`);

// 4. Bad token rejected
const bad = await fetch(`${BASE}/api/ingest/metrics`, {
  method: "POST",
  headers: { "Content-Type": "application/json", Authorization: "Bearer plk_nope" },
  body: JSON.stringify({ samples }),
});
assert(bad.status === 401, `bad token rejected with 401 (got ${bad.status})`);

// Cleanup
await sql`delete from users where id = ${user.id}`;
console.log("\nE2E PIPELINE VERIFIED ✓  (cleaned up test data)");
