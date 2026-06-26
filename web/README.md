# PulseLoop Web Backend

The server-side companion to the PulseLoop iOS app. It is the backend that the app
talks to and (in later phases) the foundation for the web app that reaches feature
parity with iOS. Built on **Next.js 16 (App Router) + React 19 + Tailwind v4 +
Drizzle ORM + Neon Postgres + Clerk auth**.

> Roadmap and status for making PulseLoop deliverable live in
> [`../docs/DELIVERY_LOOP_PROMPT.md`](../docs/DELIVERY_LOOP_PROMPT.md) and
> [`../docs/DELIVERY_PROGRESS.md`](../docs/DELIVERY_PROGRESS.md).

## What it does today

- **Account auth** via Clerk for the browser dashboard (`/dashboard`, protected by
  `src/middleware.ts`).
- **Device pairing.** The iOS app shows a 6-character code; the dashboard redeems it
  (`/api/pair/redeem`) to bind the device to the signed-in account, and the app
  exchanges it for a long-lived device token (`/api/devices/pair`).
- **Metric ingest + read.** The app uploads recent measurements
  (`/api/ingest/metrics`, authenticated by device token); the dashboard reads them
  back (`/api/metrics`, authenticated by Clerk session).

### API routes

| Route | Auth | Purpose |
|-------|------|---------|
| `POST /api/pair/redeem` | Clerk session | Redeem a pairing code → bind device to account |
| `POST /api/devices/pair` | pairing code | Exchange pairing code → device token |
| `POST /api/ingest/metrics` | device token | Upload measurements from the app/ring |
| `GET /api/metrics` | Clerk session | Read measurements for the dashboard |
| `POST /api/v1/coach/responses` | device token | AI Coach proxy: enforce credits → translate the Responses body to OpenRouter chat-completions → forward with the server key → debit usage → return a Responses-shaped body + authoritative balance (`402` when out of credits) |
| `POST /api/v1/coach/web` | Clerk session | Web Coach chat turn: same credit ledger as the device proxy but session-authed for the browser. Text-only single-shot reply via OpenRouter; returns `{reply, balance}` (`402` when out of credits) |
| `POST /api/v1/credits/validate` | device token | Validate an App Store JWS transaction with Apple → grant credits server-side (idempotent on the transaction id) → return authoritative balance |
| `GET /api/v1/account/export` | device token | Data portability: returns everything the server holds for the owner (devices, metric samples, credit balance + ledger) as one JSON document |
| `POST /api/v1/account/delete` | device token | Right to erasure: `{scope:"device"}` revokes just this device's token; `{scope:"account"}` deletes all server-side data for the owner |
| `GET /api/v1/account/me` | device token | Returns the Clerk-backed account this device is linked to (email + credit balance) and the device's own name/pairing time, so iOS can show "Signed in as …" |

> The credits data model + transactional helper (`src/lib/credits.ts`), the AI proxy, and
> the App Store validation route are all in place (Phase C/D). The proxy needs
> `OPENROUTER_API_KEY`; the validation route needs the App Store verification env (see below).

## Getting started

Requires Node 20+.

```bash
npm install
npm run dev          # http://localhost:3000
```

### Environment variables

Create `.env.local` (never commit it). With the Vercel integration you can run
`vercel env pull .env.local` instead.

| Variable | Required | Description |
|----------|----------|-------------|
| `DATABASE_URL` | yes | Neon Postgres connection string (read at import in `src/db/index.ts`). |
| `NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY` | yes | Clerk publishable key (browser). |
| `CLERK_SECRET_KEY` | yes | Clerk secret key (server). |
| `OPENROUTER_API_KEY` | for AI proxy | Server-side OpenRouter key used by `/api/v1/coach/responses` and `/api/v1/coach/web`. Never shipped to clients. |
| `OPENROUTER_COACH_MODEL` | optional | Model slug for the web Coach (`/api/v1/coach/web`). Defaults to `google/gemini-2.5-flash` (matches iOS `AIModel.smart`). |
| `APP_STORE_BUNDLE_ID` | for purchase validation | App bundle id, used to verify App Store transactions. |
| `APP_STORE_APPLE_APP_ID` | optional | Numeric App Store app id (tightens transaction verification). |
| `APP_STORE_ENVIRONMENT` | optional | `Production` or `Sandbox` (default `Sandbox`). |
| `APP_STORE_ROOT_CERTS` | for purchase validation | Comma-separated paths to Apple root CA DER files (Apple PKI → "Apple Root CA - G3"). |

When the AI proxy is live it requires `OPENROUTER_API_KEY` — the key stays on the server
and is never shipped to clients. The purchase-validation route (`/api/v1/credits/validate`)
requires the `APP_STORE_*` vars; until they're set it returns `503` and never grants on
unverified data (the app falls back to a client-side grant for sandbox/TestFlight). See
`docs/BILLING_SETUP.md`.

### Database (Drizzle + Neon)

Schema lives in `src/db/schema.ts`. Migrations are additive.

```bash
npm run db:generate   # generate a migration from schema changes
npm run db:push       # apply to the configured database
npm run db:studio     # browse data
```

> **Applying the credit tables (Phase C1):** the original tables (`users`, `devices`,
> `metric_samples`) were created on the live DB via `db:push`, so the generated baseline
> migration in `drizzle/` would try to re-create them. To add the new `credit_balances`
> and `credit_transactions` tables to an existing database, run `npm run db:push` (it diffs
> against the live schema and creates only what's missing). The committed migration files
> remain the canonical baseline for fresh environments.

## Scripts

| Script | Description |
|--------|-------------|
| `npm run dev` | Start the dev server. |
| `npm run build` | Production build (run in CI). |
| `npm run start` | Serve the production build. |
| `npm run lint` | ESLint (`eslint-config-next`). |
| `npm run db:generate` / `db:push` / `db:studio` | Drizzle migration + studio tooling. |

CI runs `npm ci && npm run lint && npm run build` (see
[`../.github/workflows/ci.yml`](../.github/workflows/ci.yml)).

## Layout

```
web/
├─ src/
│  ├─ app/
│  │  ├─ api/                 Route handlers (pairing, ingest, metrics)
│  │  ├─ dashboard/           Signed-in dashboard (pair device + metrics panel)
│  │  ├─ sign-in, sign-up/    Clerk auth pages
│  │  └─ layout.tsx           Root layout (to adopt the iOS design system — Phase G)
│  ├─ db/                     Drizzle schema + Neon client
│  ├─ lib/                    auth + device helpers
│  └─ middleware.ts           Clerk route protection
└─ drizzle.config.ts
```

## Deploy

Deploys to Vercel. Configure the environment variables above in the Vercel project,
then deploy from the dashboard or `vercel --prod`.

## Design system & portability (planned)

Per the delivery roadmap, this app will adopt the **exact PulseLoop iOS design
system** (light "life OS" theme, Newsreader + Hanken Grotesk, black primary buttons,
hairline cards — see `../.cursor/rules/design-system.mdc`), reach feature parity with
iOS over the shared backend, and be structured so a **Tauri** Windows/macOS desktop
wrapper can ship later with minimal change (platform-agnostic core + capability
interfaces). It currently uses the default dark `create-next-app` scaffold; that is
being replaced in Phase G.
