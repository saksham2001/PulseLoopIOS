# Web Parity & Generic Sync — Architecture Plan (Experience loop W1)

_Status: design accepted; W2+ implement it. Last updated: Jun 2026._

This document grounds Track W ("the web app needs all the features of the mobile
app") in the code that exists today, audits the parity gap, and specifies a
**generic record-sync foundation** that lets any module's data flow phone → cloud
→ web without bespoke endpoints per feature.

---

## 1. Where we are today

### iOS (source of truth)
- SwiftData is the on-device store. Features are modular `SubApp`s (Tasks, Notes,
  Protocol, Sleep, Workouts, Mood, Nutrition, Day Plan, Quit, Accountability,
  AI Capture) plus health metrics from HealthKit + the BLE ring.
- `CloudSyncService.sync(context:days:)` uploads **only `Measurement` rows** (heart
  rate / SpO₂ style metrics) to `POST /api/ingest/metrics`, keyed by a stable
  per-sample `clientId` for idempotent upserts. Consent- and pairing-gated.

### Backend (`web/src/db/schema.ts`)
- `users` (Clerk identity), `devices` (paired phone + ingestion token),
  `metric_samples` (the only synced domain data), `credit_balances` /
  `credit_transactions` (AI credits), `coach_sessions` (OpenRouter chat state).
- Ingestion is **device-token authenticated**; web reads are **Clerk-session**
  authenticated. Both resolve to the same `users.id`.

### Web (`web/src/app`)
- `/dashboard` (pairing + metrics panel), `/today`, `/coach` (assistant),
  `/modules` + `/modules/[id]` (read-only catalog, added in P5).
- **No** task/note/protocol/etc. surfaces — only health metrics are visible.

### Parity gap (audit)
| Domain | iOS | Web today | Parity work |
| --- | --- | --- | --- |
| Health metrics (HR/SpO₂/steps/sleep) | ✅ | ✅ read-only | minor: richer charts |
| Tasks | ✅ | ❌ | **W4 (first)** — sync + list/complete |
| Notes | ✅ | ❌ | later W iteration |
| Protocol / Nutrition / Mood / etc. | ✅ | ❌ | later W iterations |
| Modules catalog/detail | ✅ | ✅ read-only (P5) | install needs sync (future) |
| Assistant chat | ✅ | ✅ (M5) | module-aware needs sync |

The recurring blocker is the same: **only `metric_samples` syncs.** Every other
feature needs its records in the cloud first. So W2/W3 build a *generic* sync, and
W4+ light up features one at a time on top of it.

---

## 2. Design goals

1. **One generic pipe, not one endpoint per feature.** Adding a new syncable
   module should require a record mapping, not a new API route + table.
2. **Idempotent + offline-tolerant**, exactly like `metric_samples`: a stable
   `clientId` per record, upsert semantics, safe retries.
3. **Last-writer-wins per record** with an explicit `updatedAt`, which is enough
   for a single-user-multi-surface app (no real-time collaboration needed).
4. **Soft deletes** so a delete on one surface propagates instead of resurrecting.
5. **Consent- and pairing-gated**, reusing the existing device-token + Clerk auth.
6. **Schema-light:** a JSON `payload` column per record type avoids a migration
   every time a module field changes; typed views are derived server-side.

## 3. The generic record model

A single table holds every non-metric synced record, discriminated by `type`:

```
synced_records
  id            uuid pk
  user_id       uuid -> users.id (cascade)
  device_id     uuid -> devices.id (set null)
  type          text         -- "task" | "note" | "protocol_item" | ...
  client_id     text         -- stable per-record id from the device
  payload       jsonb        -- the record's fields (module-defined shape)
  updated_at    timestamptz  -- device-side last-modified (LWW key)
  deleted       boolean default false   -- soft delete (tombstone)
  created_at    timestamptz default now()
  unique (user_id, type, client_id)
  index (user_id, type, updated_at)
```

Metric samples stay in their dedicated, indexed table (high-volume, numeric,
chart-optimized). Everything else is a `synced_records` row. This keeps the hot
path fast while making the long tail of modules trivial to add.

## 4. Endpoints (W2)

- `POST /api/v1/sync/records` (device token) — batched upsert.
  Body: `{ records: [{ type, clientId, payload, updatedAt, deleted }] }`.
  Upsert on `(user_id, type, client_id)`; **LWW** — only overwrite when the
  incoming `updatedAt` ≥ stored. Returns `{ accepted, skipped }`.
- `GET /api/v1/sync/records?type=task&since=<iso>` (Clerk session) — web read.
  Returns non-deleted records of a type updated since the cursor, newest first.

Both reuse `deviceFromRequest` / `getOrCreateCurrentUser` and the same
batch-size + validation discipline as `metrics` ingestion.

## 5. iOS `DataSyncService` (W3)

A generic counterpart to `CloudSyncService.sync` that walks a registry of
`SyncableRecordProvider`s — one per module — each of which knows how to:
- `fetchDirty(since:context:)` → `[SyncRecord]` (its rows mapped to `{type,
  clientId, payload, updatedAt, deleted}`), and
- (later, for read-back) `apply(_:context:)` for two-way sync.

W3 ships **upload** first (phone → cloud), mirroring today's metric flow, so the
web can read. Two-way (cloud → phone) is a later enhancement; the table already
supports it. Tasks provides the first `SyncableRecordProvider` (W4).

## 6. Per-feature parity (W4+)

For each feature, in priority order (Tasks first):
1. Add a `SyncableRecordProvider` on iOS mapping its SwiftData model → payload.
2. Add a typed web reader + page (`/tasks`, …) that renders `synced_records`.
3. Mutations from web (e.g. complete a task) write a `synced_records` row the
   phone reconciles on next two-way sync (or, interim, are read-only on web).

## 7. Out of scope for Track W
- Real-time/collaborative editing, multi-device conflict UIs (LWW is sufficient).
- Moving module *install state* to the cloud (web stays catalog-read-only until a
  later initiative); the assistant's module-awareness on web waits on that.

---

### Acceptance for W1
- [x] Parity gap audited against real code (tables, endpoints, services).
- [x] Generic `synced_records` model + LWW + soft-delete specified.
- [x] Upload-first iOS `DataSyncService` shape defined with Tasks as pilot.
- [x] Endpoint contracts + auth model fixed for W2.
