"use client";

import { useEffect, useState } from "react";
import { PulseCard } from "@/components/ui";

interface RecordPayload {
  title?: string;
  subtitle?: string;
  detail?: string;
  date?: string;
  status?: string;
  [key: string]: unknown;
}

interface SyncedRecord {
  clientId: string;
  type: string;
  payload: RecordPayload;
  updatedAt: string;
  deleted: boolean;
}

function formatDate(iso: string | undefined) {
  if (!iso) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  return d.toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
}

export function RecordsPanel({ type }: { type: string }) {
  const [records, setRecords] = useState<SyncedRecord[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    (async () => {
      try {
        const res = await fetch(
          `/api/v1/sync/records?type=${encodeURIComponent(type)}&limit=500`,
        );
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const data = await res.json();
        if (active) setRecords(data.records);
      } catch {
        if (active) setError("Couldn't load this data.");
      }
    })();
    return () => {
      active = false;
    };
  }, [type]);

  if (error) {
    return <p className="text-alert text-sm">{error}</p>;
  }

  if (!records) {
    return (
      <div className="border-border-hairline bg-fill-subtle h-40 animate-pulse rounded-[14px] border" />
    );
  }

  if (records.length === 0) {
    return (
      <section className="border-border-strong rounded-[14px] border border-dashed p-8 text-center">
        <p className="text-text-secondary text-[15px]">
          Nothing here yet. Use this feature in the iPhone app and let it sync.
        </p>
      </section>
    );
  }

  return (
    <PulseCard>
      <ul className="divide-border-hairline divide-y">
        {records.map((r) => {
          const date = formatDate(r.payload.date ?? r.updatedAt);
          const done =
            r.payload.status === "done" || r.payload.status === "cancelled";
          return (
            <li key={r.clientId} className="flex items-start gap-3 py-3 first:pt-0 last:pb-0">
              <div className="min-w-0 flex-1">
                <p
                  className={
                    done
                      ? "text-text-muted text-[15px] line-through"
                      : "text-text-primary text-[15px] font-medium"
                  }
                >
                  {r.payload.title || "Untitled"}
                </p>
                {r.payload.subtitle && (
                  <p className="text-text-secondary mt-0.5 text-[13px]">
                    {r.payload.subtitle}
                  </p>
                )}
                {r.payload.detail && (
                  <p className="text-text-muted mt-0.5 text-[13px]">
                    {r.payload.detail}
                  </p>
                )}
              </div>
              {date && (
                <span className="text-text-muted shrink-0 pt-0.5 text-xs">
                  {date}
                </span>
              )}
            </li>
          );
        })}
      </ul>
    </PulseCard>
  );
}
