"use client";

import { useCallback, useEffect, useState } from "react";

export interface SyncRecord<P = Record<string, unknown>> {
  clientId: string;
  type: string;
  payload: P;
  updatedAt: string;
}

/**
 * Clerk-session record list for one `type`, backed by `/api/records`. Returns the
 * live records plus optimistic `upsert` / `remove` mutators that persist
 * server-side. Used by Tasks, Notes, Protocol, Journal, Meals, Mood, …
 */
export function useRecords<P = Record<string, unknown>>(type: string) {
  const [records, setRecords] = useState<SyncRecord<P>[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    (async () => {
      try {
        const res = await fetch(
          `/api/records?type=${encodeURIComponent(type)}&limit=1000`,
        );
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const data = await res.json();
        if (active) setRecords(data.records ?? []);
      } catch {
        if (active) setError("Couldn't load data.");
      }
    })();
    return () => {
      active = false;
    };
  }, [type]);

  const upsert = useCallback(
    async (payload: P, clientId?: string): Promise<SyncRecord<P>> => {
      const id = clientId ?? crypto.randomUUID();
      const optimistic: SyncRecord<P> = {
        clientId: id,
        type,
        payload,
        updatedAt: new Date().toISOString(),
      };
      setRecords((prev) => {
        const list = prev ?? [];
        const idx = list.findIndex((r) => r.clientId === id);
        if (idx >= 0) {
          const next = [...list];
          next[idx] = optimistic;
          return next;
        }
        return [optimistic, ...list];
      });
      try {
        const res = await fetch("/api/records", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ type, clientId: id, payload }),
        });
        if (res.ok) {
          const saved = await res.json();
          setRecords((prev) =>
            (prev ?? []).map((r) =>
              r.clientId === id ? { ...r, updatedAt: saved.updatedAt } : r,
            ),
          );
        }
      } catch {
        // keep optimistic value
      }
      return optimistic;
    },
    [type],
  );

  const remove = useCallback(
    async (clientId: string) => {
      setRecords((prev) => (prev ?? []).filter((r) => r.clientId !== clientId));
      try {
        await fetch(
          `/api/records?type=${encodeURIComponent(type)}&clientId=${encodeURIComponent(clientId)}`,
          { method: "DELETE" },
        );
      } catch {
        // optimistic removal already applied
      }
    },
    [type],
  );

  return { records, error, loading: records === null, upsert, remove, setRecords };
}
