import { NextResponse } from "next/server";
import { asc, eq } from "drizzle-orm";
import { db } from "@/db";
import {
  creditBalances,
  creditTransactions,
  devices,
  metricSamples,
} from "@/db/schema";
import { deviceFromRequest } from "@/lib/device";

/**
 * Device-authenticated data export (GDPR / App Store "data portability").
 *
 * Returns everything the server holds for the device's owner — paired devices,
 * uploaded metric samples, the credit balance, and the credit ledger — as a
 * single JSON document the iOS app saves / shares.
 *
 * Auth: `Authorization: Bearer <device token>`
 */
export async function GET(req: Request) {
  const device = await deviceFromRequest(req);
  if (!device) {
    return NextResponse.json({ error: "unauthorized" }, { status: 401 });
  }

  const userId = device.userId;

  const [userDevices, samples, balanceRows, transactions] = await Promise.all([
    db
      .select({
        id: devices.id,
        name: devices.name,
        pairedAt: devices.pairedAt,
        lastSeenAt: devices.lastSeenAt,
        createdAt: devices.createdAt,
      })
      .from(devices)
      .where(eq(devices.userId, userId))
      .orderBy(asc(devices.createdAt)),
    db
      .select({
        kind: metricSamples.kind,
        value: metricSamples.value,
        unit: metricSamples.unit,
        recordedAt: metricSamples.recordedAt,
        clientId: metricSamples.clientId,
      })
      .from(metricSamples)
      .where(eq(metricSamples.userId, userId))
      .orderBy(asc(metricSamples.recordedAt)),
    db
      .select({ balance: creditBalances.balance, updatedAt: creditBalances.updatedAt })
      .from(creditBalances)
      .where(eq(creditBalances.userId, userId))
      .limit(1),
    db
      .select({
        delta: creditTransactions.delta,
        balanceAfter: creditTransactions.balanceAfter,
        kind: creditTransactions.kind,
        inputTokens: creditTransactions.inputTokens,
        outputTokens: creditTransactions.outputTokens,
        createdAt: creditTransactions.createdAt,
      })
      .from(creditTransactions)
      .where(eq(creditTransactions.userId, userId))
      .orderBy(asc(creditTransactions.createdAt)),
  ]);

  return NextResponse.json({
    exportedAt: new Date().toISOString(),
    schemaVersion: 1,
    account: {
      userId,
      devices: userDevices,
      credits: {
        balance: balanceRows[0]?.balance ?? 0,
        updatedAt: balanceRows[0]?.updatedAt ?? null,
        transactions,
      },
      metrics: {
        count: samples.length,
        samples,
      },
    },
  });
}
