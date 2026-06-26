"use client";

import { useEffect, useState } from "react";
import { PageHeader } from "@/components/ui";
import { PairDevice } from "@/app/dashboard/pair-device";

interface Device {
  id: string;
  name: string | null;
  pairedAt: string | null;
  lastSeenAt: string | null;
}

function relWhen(iso: string | null): string {
  if (!iso) return "—";
  const mins = Math.round((Date.now() - new Date(iso).getTime()) / 60000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.round(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  return `${Math.round(hrs / 24)}d ago`;
}

export function ConnectScreen() {
  const [devices, setDevices] = useState<Device[] | null>(null);

  useEffect(() => {
    let active = true;
    (async () => {
      try {
        const res = await fetch("/api/devices");
        if (res.ok && active) {
          const data = await res.json();
          setDevices(data.devices ?? []);
        }
      } catch {
        if (active) setDevices([]);
      }
    })();
    return () => {
      active = false;
    };
  }, []);

  const connected = (devices?.length ?? 0) > 0;

  const sources = [
    {
      emoji: "📱",
      name: "iPhone",
      detail: connected
        ? `${devices!.length} paired device${devices!.length === 1 ? "" : "s"}`
        : "Not paired yet",
      status: connected ? "Connected" : "Connect",
      ok: connected,
    },
    {
      emoji: "❤️",
      name: "Apple Health",
      detail: "Heart rate, sleep, steps & workouts",
      status: connected ? "Syncing" : "Pending",
      ok: connected,
    },
    {
      emoji: "✨",
      name: "AI Coach",
      detail: "OpenRouter-powered insights & capture",
      status: "Connected",
      ok: true,
    },
  ];

  return (
    <div>
      <PageHeader title="Connect" subtitle="Where your data flows in from." />

      <div className="mt-7">
        <PairDevice />
      </div>

      <div className="mt-5 flex flex-col gap-2.5">
        {sources.map((c) => (
          <div
            key={c.name}
            className="bg-background border-border-hairline flex items-center gap-3.5 rounded-[14px] border px-[18px] py-3.5 shadow-sm"
          >
            <span className="text-[24px]">{c.emoji}</span>
            <div className="min-w-0 flex-1">
              <div className="text-[15px] font-semibold">{c.name}</div>
              <div className="text-text-muted text-[13px]">{c.detail}</div>
            </div>
            <span
              className={`shrink-0 rounded-full px-3 py-1 text-[12.5px] font-semibold ${
                c.ok
                  ? "bg-success-bg text-success"
                  : "bg-fill-subtle text-text-secondary"
              }`}
            >
              {c.status}
            </span>
          </div>
        ))}
      </div>

      {connected && (
        <>
          <div className="text-text-muted mt-9 text-[11px] font-semibold tracking-[0.09em] uppercase">
            Paired devices
          </div>
          <div className="mt-3 flex flex-col gap-2.5">
            {devices!.map((d) => (
              <div
                key={d.id}
                className="bg-background border-border-hairline flex items-center gap-3.5 rounded-[14px] border px-[18px] py-3.5 shadow-sm"
              >
                <span className="text-[20px]">📱</span>
                <div className="min-w-0 flex-1">
                  <div className="text-[15px] font-semibold">
                    {d.name ?? "iPhone"}
                  </div>
                  <div className="text-text-muted text-[13px]">
                    Last seen {relWhen(d.lastSeenAt)}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </>
      )}
    </div>
  );
}
