import { readFileSync } from "node:fs";
import {
  SignedDataVerifier,
  Environment,
  type JWSTransactionDecodedPayload,
} from "@apple/app-store-server-library";

/**
 * App Store transaction verification (roadmap D2).
 *
 * Wraps Apple's `SignedDataVerifier` so the credit-grant route can verify the signed
 * JWS transaction the app receives from StoreKit before granting server-side credits.
 *
 * Configuration (all via env so nothing secret is committed):
 * - `APP_STORE_BUNDLE_ID`        — your app bundle id (e.g. com.pulseloop.app)
 * - `APP_STORE_APPLE_APP_ID`     — numeric App Store app id (appAppleId)
 * - `APP_STORE_ENVIRONMENT`      — "Production" | "Sandbox" (default Sandbox)
 * - `APP_STORE_ROOT_CERTS`       — comma-separated paths to Apple root CA DER files
 *                                  (download the "Apple Root CA - G3" cert from Apple PKI).
 *
 * Until these are set the verifier is unavailable and the route reports a clear
 * "unconfigured" error rather than trusting unverified client data.
 */

let cachedVerifier: SignedDataVerifier | null | undefined;

function loadVerifier(): SignedDataVerifier | null {
  if (cachedVerifier !== undefined) return cachedVerifier;

  const bundleId = process.env.APP_STORE_BUNDLE_ID;
  const appAppleIdRaw = process.env.APP_STORE_APPLE_APP_ID;
  const certPaths = (process.env.APP_STORE_ROOT_CERTS ?? "")
    .split(",")
    .map((p) => p.trim())
    .filter(Boolean);

  if (!bundleId || certPaths.length === 0) {
    cachedVerifier = null;
    return null;
  }

  const environment =
    process.env.APP_STORE_ENVIRONMENT === "Production"
      ? Environment.PRODUCTION
      : Environment.SANDBOX;

  let rootCerts: Buffer[];
  try {
    rootCerts = certPaths.map((p) => readFileSync(p));
  } catch {
    cachedVerifier = null;
    return null;
  }

  const appAppleId = appAppleIdRaw ? Number(appAppleIdRaw) : undefined;

  cachedVerifier = new SignedDataVerifier(
    rootCerts,
    // enableOnlineChecks: revocation checks against Apple OCSP.
    true,
    environment,
    bundleId,
    appAppleId,
  );
  return cachedVerifier;
}

export interface VerifiedTransaction {
  productId: string;
  transactionId: string;
  bundleId?: string;
}

export type VerifyResult =
  | { ok: true; transaction: VerifiedTransaction }
  | { ok: false; reason: "unconfigured" | "invalid" };

/**
 * Verify a signed JWS transaction and return the trusted product/transaction ids.
 * Returns `unconfigured` when the verifier env isn't set, `invalid` when verification
 * fails — the caller must NOT grant credits in either case.
 */
export async function verifyTransaction(
  signedTransaction: string,
): Promise<VerifyResult> {
  const verifier = loadVerifier();
  if (!verifier) return { ok: false, reason: "unconfigured" };

  let payload: JWSTransactionDecodedPayload;
  try {
    payload = await verifier.verifyAndDecodeTransaction(signedTransaction);
  } catch {
    return { ok: false, reason: "invalid" };
  }

  if (!payload.productId || !payload.transactionId) {
    return { ok: false, reason: "invalid" };
  }

  return {
    ok: true,
    transaction: {
      productId: payload.productId,
      transactionId: payload.transactionId,
      bundleId: payload.bundleId,
    },
  };
}
