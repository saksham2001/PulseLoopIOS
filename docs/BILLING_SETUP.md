# Billing setup (AI credits)

PulseLoop sells **consumable** AI-credit packs via StoreKit 2. Buying a pack grants
credits to the local `CreditsLedger` (and, once the server validation endpoint is live —
roadmap D2 — to the server-authoritative ledger). The coach and other AI features debit
those credits per use.

## Products

The app expects exactly these three consumable product ids (see
`PulseLoop/Services/CreditStore.swift` → `creditsByProductID`):

| Product ID | Credits | Suggested price (USD) |
|------------|---------|-----------------------|
| `com.pulseloop.credits.100`  | 100  | $0.99 |
| `com.pulseloop.credits.500`  | 500  | $3.99 |
| `com.pulseloop.credits.1200` | 1200 | $7.99 |

> If you change ids/prices/credit amounts, update **both** `CreditStore.creditsByProductID`
> and `PulseLoop.storekit`, and the App Store Connect products. The credit amount is decided
> by the **app** (the product id → credits map), not by StoreKit, so it stays consistent
> regardless of price.

## Local testing (StoreKit configuration file)

A local StoreKit configuration lives at `PulseLoop.storekit` so purchases work in the
Simulator/dev without App Store Connect. To enable it:

1. In Xcode: **Product → Scheme → Edit Scheme… → Run → Options**.
2. Set **StoreKit Configuration** to `PulseLoop.storekit`.
3. Run the app, open **Settings → AI Credits**, and the three packs should load. Test
   purchases will grant credits through `CreditStore.handle(verification:)`.

You can simulate failures via the **StoreKit Configuration** editor (the `_storeKitErrors`
toggles) or Xcode's Transaction Manager (**Debug → StoreKit → Manage Transactions**).

## App Store Connect (production)

1. In App Store Connect, open your app → **Monetization → In-App Purchases**.
2. Create three **Consumable** in-app purchases with the product ids above.
3. For each: set a reference name, pricing, and at least one localization (display name +
   description). Submit them for review with the app build (consumables can be reviewed
   alongside the binary).
4. Ensure the **In-App Purchase** capability is enabled for the app target and the bundle id
   matches the App Store Connect record.
5. Sandbox-test with a Sandbox Apple ID before release.

## Server-side validation (roadmap D2 — not yet implemented)

For a paid build the purchase should also be validated server-side so the
server-authoritative balance is the source of truth and credits can't be granted by a
tampered client. Planned flow:

- App sends the App Store **JWS transaction** (or transaction id) to a web endpoint.
- Server verifies it with Apple (App Store Server API / signed transaction verification),
  maps the product id → credits, and `grantCredit(...)` with the **transaction id as the
  idempotency `referenceId`** (see `web/src/lib/credits.ts`) so a replay can't double-grant.
- Server returns the new authoritative balance; the app syncs it via
  `CreditsLedger.syncAuthoritativeBalance`.

Until D2 lands, credits are granted client-side on purchase (fine for TestFlight/sandbox and
an initial release, but not tamper-proof).
