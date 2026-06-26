import {
  pgTable,
  uuid,
  text,
  integer,
  timestamp,
  doublePrecision,
  boolean,
  jsonb,
  index,
  unique,
} from "drizzle-orm/pg-core";

/**
 * App users. We key off Clerk's user id (string) as the canonical identity so
 * the web session and the device-paired uploads resolve to the same person.
 */
export const users = pgTable("users", {
  id: uuid("id").defaultRandom().primaryKey(),
  clerkId: text("clerk_id").notNull().unique(),
  email: text("email"),
  createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
});

/**
 * A paired iOS device. The phone authenticates ingestion with `token` (a long
 * random secret), which is exchanged once via a short-lived pairing `code`
 * the signed-in user enters/scans in the app.
 */
export const devices = pgTable(
  "devices",
  {
    id: uuid("id").defaultRandom().primaryKey(),
    userId: uuid("user_id")
      .references(() => users.id, { onDelete: "cascade" })
      .notNull(),
    name: text("name").notNull().default("iPhone"),
    // Long-lived ingestion secret (null until pairing completes).
    token: text("token").unique(),
    // Short-lived pairing code shown on web, entered on device.
    pairingCode: text("pairing_code").unique(),
    pairingExpiresAt: timestamp("pairing_expires_at", { withTimezone: true }),
    pairedAt: timestamp("paired_at", { withTimezone: true }),
    lastSeenAt: timestamp("last_seen_at", { withTimezone: true }),
    createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
  },
  (t) => [index("devices_user_idx").on(t.userId)],
);

/**
 * One health metric reading uploaded from a device. `clientId` is a stable id
 * generated on-device so repeated syncs are idempotent (upsert on it).
 */
export const metricSamples = pgTable(
  "metric_samples",
  {
    id: uuid("id").defaultRandom().primaryKey(),
    userId: uuid("user_id")
      .references(() => users.id, { onDelete: "cascade" })
      .notNull(),
    deviceId: uuid("device_id").references(() => devices.id, {
      onDelete: "set null",
    }),
    // e.g. "heart_rate", "spo2", "steps", "sleep_minutes".
    kind: text("kind").notNull(),
    value: doublePrecision("value").notNull(),
    unit: text("unit"),
    recordedAt: timestamp("recorded_at", { withTimezone: true }).notNull(),
    // Stable per-sample id from the device for idempotent upserts.
    clientId: text("client_id").notNull(),
    createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
  },
  (t) => [
    unique("metric_samples_user_client_uq").on(t.userId, t.clientId),
    index("metric_samples_user_kind_time_idx").on(t.userId, t.kind, t.recordedAt),
  ],
);

/**
 * Server-authoritative AI credit balance — one row per user. This is the source
 * of truth the iOS client syncs to (`CreditsLedger.syncAuthoritativeBalance`).
 * Mutations must go through a transaction that also appends a `creditTransactions`
 * row so the balance and ledger never drift.
 */
export const creditBalances = pgTable("credit_balances", {
  userId: uuid("user_id")
    .references(() => users.id, { onDelete: "cascade" })
    .primaryKey(),
  balance: integer("balance").notNull().default(0),
  updatedAt: timestamp("updated_at", { withTimezone: true }).defaultNow().notNull(),
});

/**
 * Immutable AI credit ledger. Every debit (metered AI usage via the proxy) and
 * credit (initial grant, validated StoreKit purchase, refund) is recorded here.
 *
 * - `delta` is negative for usage, positive for grants/purchases.
 * - `balanceAfter` snapshots the balance immediately after this entry.
 * - `kind` mirrors the iOS `AIUsageKind` (`coach_turn`, `image_analysis`, …) plus
 *   purchase/grant kinds.
 * - `referenceId` dedupes external events: the App Store transaction id for a
 *   purchase, or the proxy request id for a usage debit, so retries are idempotent.
 */
export const creditTransactions = pgTable(
  "credit_transactions",
  {
    id: uuid("id").defaultRandom().primaryKey(),
    userId: uuid("user_id")
      .references(() => users.id, { onDelete: "cascade" })
      .notNull(),
    delta: integer("delta").notNull(),
    balanceAfter: integer("balance_after").notNull(),
    kind: text("kind").notNull(),
    inputTokens: integer("input_tokens"),
    outputTokens: integer("output_tokens"),
    // Idempotency key for external events (App Store txn id / proxy request id).
    referenceId: text("reference_id"),
    createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
  },
  (t) => [
    index("credit_transactions_user_time_idx").on(t.userId, t.createdAt),
    unique("credit_transactions_reference_uq").on(t.referenceId),
  ],
);

export type User = typeof users.$inferSelect;
export type Device = typeof devices.$inferSelect;
export type MetricSample = typeof metricSamples.$inferSelect;

/**
 * Generic per-record sync store for every non-metric module (Tasks, Notes,
 * Protocol items, …). Discriminated by `type`; the record's fields live in the
 * `payload` JSON so adding a module needs a mapping, not a migration.
 *
 * - `clientId` is the device-stable id; upsert on `(userId, type, clientId)`.
 * - `updatedAt` is the device-side last-modified used for last-writer-wins: an
 *   incoming write only overwrites when its `updatedAt` is >= the stored one.
 * - `deleted` is a tombstone so deletes propagate instead of resurrecting.
 *
 * High-volume numeric health data stays in `metric_samples`; this is the long
 * tail of structured records.
 */
export const syncedRecords = pgTable(
  "synced_records",
  {
    id: uuid("id").defaultRandom().primaryKey(),
    userId: uuid("user_id")
      .references(() => users.id, { onDelete: "cascade" })
      .notNull(),
    deviceId: uuid("device_id").references(() => devices.id, {
      onDelete: "set null",
    }),
    // e.g. "task", "note", "protocol_item".
    type: text("type").notNull(),
    // Stable per-record id from the device for idempotent upserts.
    clientId: text("client_id").notNull(),
    // Module-defined record shape.
    payload: jsonb("payload").notNull(),
    // Device-side last-modified; the last-writer-wins key.
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull(),
    // Soft-delete tombstone so deletes propagate.
    deleted: boolean("deleted").notNull().default(false),
    createdAt: timestamp("created_at", { withTimezone: true }).defaultNow().notNull(),
  },
  (t) => [
    unique("synced_records_user_type_client_uq").on(t.userId, t.type, t.clientId),
    index("synced_records_user_type_time_idx").on(t.userId, t.type, t.updatedAt),
  ],
);

export type SyncedRecord = typeof syncedRecords.$inferSelect;
export type CreditBalance = typeof creditBalances.$inferSelect;
export type CreditTransaction = typeof creditTransactions.$inferSelect;

/**
 * Conversation state for the OpenRouter-backed Coach proxy.
 *
 * OpenRouter (unlike OpenAI's Responses API) is stateless and has no
 * `previous_response_id`, but the iOS orchestrator relies on it to continue a
 * multi-round tool loop sending only the new tool outputs. So the proxy persists
 * the running chat-completions `messages[]` (plus the deferred `tool_calls` of the
 * last assistant turn) here, keyed on the response id we hand back; the next turn
 * looks the row up by `previous_response_id` and resumes it.
 *
 * Rows are scoped to a user, short-lived, and safe to prune (a missing session
 * just means the turn starts fresh from the input it carries).
 */
export const coachSessions = pgTable(
  "coach_sessions",
  {
    // The response id we returned for the turn that produced this state.
    responseId: text("response_id").primaryKey(),
    userId: uuid("user_id")
      .references(() => users.id, { onDelete: "cascade" })
      .notNull(),
    // Serialized chat-completions message history.
    messages: text("messages").notNull(),
    // Serialized tool_calls from the last assistant turn awaiting their results.
    pendingToolCalls: text("pending_tool_calls").notNull().default("[]"),
    // Whether the one-time JSON-shape system nudge was already injected.
    injectedJson: integer("injected_json").notNull().default(0),
    updatedAt: timestamp("updated_at", { withTimezone: true }).defaultNow().notNull(),
  },
  (t) => [index("coach_sessions_user_idx").on(t.userId)],
);

export type CoachSession = typeof coachSessions.$inferSelect;

/**
 * Per-user web workspace preferences — one row per user. Holds the JSON blobs the
 * web app needs but that aren't per-record sync data:
 *
 * - `modules`    : map of module id → enabled boolean. Source of truth for which
 *                  nav items + Home feed sections + routes are visible on the web.
 * - `homeLayout` : ordered list of Home feed section ids + their span (1×/2×),
 *                  driving the modular feed's reorder / resize state.
 * - `theme`      : "light" | "dark" workspace appearance.
 * - `permissions`: map of privacy permission id → on boolean.
 *
 * Everything is optional; a missing key falls back to the app defaults so a fresh
 * user renders the prototype's default workspace.
 */
export const userSettings = pgTable("user_settings", {
  userId: uuid("user_id")
    .references(() => users.id, { onDelete: "cascade" })
    .primaryKey(),
  modules: jsonb("modules"),
  homeLayout: jsonb("home_layout"),
  theme: text("theme"),
  permissions: jsonb("permissions"),
  updatedAt: timestamp("updated_at", { withTimezone: true })
    .defaultNow()
    .notNull(),
});

export type UserSettings = typeof userSettings.$inferSelect;