"use client";

import { useEffect, useMemo, useState } from "react";
import { PageHeader } from "@/components/ui";

interface Sample {
  kind: string;
  value: number;
  recordedAt: string;
}

const STAGES = [
  { name: "Awake", key: "awake", color: "rgba(180,69,58,.55)", pct: 6 },
  { name: "REM", key: "rem", color: "rgba(107,95,160,.6)", pct: 22 },
  { name: "Core", key: "core", color: "rgba(74,127,181,.6)", pct: 52 },
  { name: "Deep", key: "deep", color: "rgba(46,89,132,.75)", pct: 20 },
];

function fmtDur(min: number): string {
  const h = Math.floor(min / 60);
  const m = Math.round(min % 60);
  return `${h}h ${String(m).padStart(2, "0")}m`;
}

export function SleepScreen() {
  const [samples, setSamples] = useState<Sample[] | null>(null);

  useEffect(() => {
    let active = true;
    (async () => {
      try {
        const res = await fetch("/api/metrics?days=2");
        if (res.ok && active) {
          const data = await res.json();
          setSamples(data.samples ?? []);
        }
      } catch {
        if (active) setSamples([]);
      }
    })();
    return () => {
      active = false;
    };
  }, []);

  const { minutes, score, hasData } = useMemo(() => {
    const sleep = (samples ?? [])
      .filter((s) => s.kind === "sleep_minutes")
      .sort(
        (a, b) =>
          new Date(b.recordedAt).getTime() - new Date(a.recordedAt).getTime(),
      );
    if (sleep.length === 0) return { minutes: 441, score: 84, hasData: false };
    const mins = sleep[0].value;
    // Simple readiness-style score: scaled to a 7.5h target, capped 0–100.
    const sc = Math.max(0, Math.min(100, Math.round((mins / 450) * 90 + 10)));
    return { minutes: mins, score: sc, hasData: true };
  }, [samples]);

  return (
    <div>
      <PageHeader
        title="Sleep"
        subtitle={hasData ? "Last night · synced from iPhone." : "Last night · sample data until your iPhone syncs sleep."}
      />

      <div className="mt-7 grid grid-cols-[260px_1fr] items-start gap-5 max-[760px]:grid-cols-1">
        <section className="bg-background border-border-hairline rounded-[16px] border p-[22px] text-center shadow-sm">
          <div className="text-text-muted text-[11px] font-semibold tracking-[0.09em] uppercase">
            Sleep score
          </div>
          <div className="my-2 font-serif text-[64px] leading-none">{score}</div>
          <div className="text-text-secondary text-[14px] font-medium">
            {fmtDur(minutes)} · {score >= 80 ? "Good" : score >= 60 ? "Fair" : "Low"}
          </div>
        </section>

        <section className="bg-background border-border-hairline rounded-[16px] border p-[22px] shadow-sm">
          <div className="text-text-muted mb-4 text-[11px] font-semibold tracking-[0.09em] uppercase">
            Hypnogram
          </div>
          <div className="bg-fill-subtle mb-4 flex h-16 overflow-hidden rounded-[10px]">
            {STAGES.map((s) => (
              <div
                key={s.key}
                style={{ width: `${s.pct}%`, background: s.color }}
                title={`${s.name} · ${s.pct}%`}
              />
            ))}
          </div>
          <div className="flex flex-col gap-2">
            {STAGES.map((s) => (
              <div key={s.key} className="flex items-center gap-2.5">
                <span
                  className="h-3 w-3 rounded-[3px]"
                  style={{ background: s.color }}
                />
                <span className="text-[14px] font-medium">{s.name}</span>
                <span className="text-text-muted ml-auto text-[13.5px]">
                  {fmtDur((minutes * s.pct) / 100)}
                </span>
              </div>
            ))}
          </div>
        </section>
      </div>
    </div>
  );
}
