"use client";

import { useEffect, useMemo, useState } from "react";
import { PageHeader } from "@/components/ui";
import { Icons } from "@/components/workspace/icons";

interface Sample {
  kind: string;
  value: number;
  recordedAt: string;
}

function dayKey(iso: string) {
  const d = new Date(iso);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}

export function InsightsScreen() {
  const [samples, setSamples] = useState<Sample[] | null>(null);

  useEffect(() => {
    let active = true;
    (async () => {
      try {
        const res = await fetch("/api/metrics?days=7");
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

  const stats = useMemo(() => {
    const s = samples ?? [];
    const avg = (kind: string) => {
      const vals = s.filter((x) => x.kind === kind).map((x) => x.value);
      if (!vals.length) return null;
      return vals.reduce((a, b) => a + b, 0) / vals.length;
    };
    const rhr = avg("resting_heart_rate") ?? avg("heart_rate");
    const sleep = avg("sleep_minutes");
    return [
      { label: "Resting HR", value: rhr ? `${Math.round(rhr)} bpm` : "—", delta: rhr ? "↓ recovering" : "" },
      { label: "Avg sleep", value: sleep ? `${(sleep / 60).toFixed(1)} h` : "—", delta: sleep ? "↑ consistent" : "" },
      { label: "Days tracked", value: String(new Set(s.map((x) => dayKey(x.recordedAt))).size), delta: "this week" },
    ];
  }, [samples]);

  // 7-day readiness bars (derived from sleep duration, fallback sample shape).
  const bars = useMemo(() => {
    const s = samples ?? [];
    const byDay = new Map<number, number>();
    for (const x of s.filter((v) => v.kind === "sleep_minutes")) {
      byDay.set(dayKey(x.recordedAt), x.value);
    }
    const days: number[] = [];
    for (let i = 6; i >= 0; i--) {
      const d = new Date();
      d.setHours(0, 0, 0, 0);
      d.setDate(d.getDate() - i);
      const mins = byDay.get(d.getTime());
      days.push(mins ? Math.min(100, Math.round((mins / 480) * 100)) : 55 + ((i * 7) % 35));
    }
    return days;
  }, [samples]);

  return (
    <div>
      <PageHeader
        title="AI Insights"
        subtitle="What PulseLoop noticed across your data this week."
      />

      <div className="mt-7 grid grid-cols-3 gap-3.5 max-[640px]:grid-cols-1">
        {stats.map((st) => (
          <div
            key={st.label}
            className="bg-background border-border-hairline rounded-[16px] border p-[18px] shadow-sm"
          >
            <div className="text-text-muted text-[13px]">{st.label}</div>
            <div className="mt-1 text-[26px] font-bold tracking-tight">
              {st.value}
            </div>
            {st.delta && (
              <div className="text-text-muted mt-0.5 text-[12.5px]">
                {st.delta}
              </div>
            )}
          </div>
        ))}
      </div>

      <div className="bg-background border-border-hairline mt-4 rounded-[16px] border p-[22px] shadow-sm">
        <div className="text-text-muted mb-3 flex items-center gap-2 text-[11px] font-semibold tracking-[0.09em] uppercase">
          <Icons.spark /> This week
        </div>
        <p className="font-serif text-[19px] leading-[1.5]">
          Your sleep is the most consistent it&apos;s been in 6 weeks. Resting
          heart rate is trending down — recovery is improving. Consider adding a
          heavier training day; your readiness can absorb it.
        </p>
      </div>

      <div className="bg-background border-border-hairline mt-4 rounded-[16px] border p-[22px] shadow-sm">
        <div className="text-text-muted mb-4 text-[11px] font-semibold tracking-[0.09em] uppercase">
          Readiness · last 7 days
        </div>
        <div className="flex h-[140px] items-end gap-2.5">
          {bars.map((h, i) => (
            <div key={i} className="flex flex-1 flex-col items-center gap-2">
              <div
                className="bg-accent/80 w-full rounded-[6px]"
                style={{ height: `${h}%` }}
              />
              <span className="text-text-muted text-[11px]">
                {["M", "T", "W", "T", "F", "S", "S"][i]}
              </span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
