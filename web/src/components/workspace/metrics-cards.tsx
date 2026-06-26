"use client";

import { useEffect, useMemo, useState } from "react";
import { PulseCard, PulseSectionLabel } from "@/components/ui";
import { pulseSemantic } from "@/lib/tokens";

export interface Sample {
  id: string;
  kind: string;
  value: number;
  unit: string | null;
  recordedAt: string;
}

type Stat = "latest" | "sumToday" | "lastNight";

interface MetricSpec {
  kind: string;
  label: string;
  color: string;
  stat: Stat;
  unit?: string;
  format?: (v: number) => string;
}

// Mirrors the iOS metrics surface: a small set of headline metrics, each
// summarized the way that metric is naturally read.
const METRICS: MetricSpec[] = [
  { kind: "heart_rate", label: "Heart rate", color: pulseSemantic.heartRate, stat: "latest", unit: "bpm" },
  { kind: "spo2", label: "Blood oxygen", color: pulseSemantic.spo2, stat: "latest", unit: "%" },
  { kind: "steps", label: "Steps today", color: pulseSemantic.steps, stat: "sumToday", format: (v) => Math.round(v).toLocaleString() },
  {
    kind: "sleep_minutes",
    label: "Last night's sleep",
    color: pulseSemantic.sleep,
    stat: "lastNight",
    format: (v) => {
      const h = Math.floor(v / 60);
      const m = Math.round(v % 60);
      return m ? `${h}h ${m}m` : `${h}h`;
    },
  },
];

function startOfToday(): number {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}

function summarize(
  spec: MetricSpec,
  samples: Sample[],
): { display: string; sub: string } | null {
  const mine = samples
    .filter((s) => s.kind === spec.kind)
    .sort(
      (a, b) =>
        new Date(a.recordedAt).getTime() - new Date(b.recordedAt).getTime(),
    );
  if (mine.length === 0) return null;

  const fmt = (v: number) =>
    spec.format ? spec.format(v) : `${Math.round(v * 10) / 10}`;
  const dayStart = startOfToday();

  if (spec.stat === "latest") {
    const last = mine[mine.length - 1];
    return {
      display: `${fmt(last.value)}${spec.unit ? ` ${spec.unit}` : ""}`,
      sub: `as of ${new Date(last.recordedAt).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })}`,
    };
  }

  if (spec.stat === "sumToday") {
    const today = mine.filter((s) => new Date(s.recordedAt).getTime() >= dayStart);
    if (today.length === 0) return { display: "0", sub: "no readings today yet" };
    const total = today.reduce((acc, s) => acc + s.value, 0);
    return { display: fmt(total), sub: `${today.length} readings` };
  }

  const last = mine[mine.length - 1];
  return {
    display: fmt(last.value),
    sub: new Date(last.recordedAt).toLocaleDateString([], { weekday: "long" }),
  };
}

/** Headline health-metric cards backed by `/api/metrics`. */
export function MetricsCards({ days = 3 }: { days?: number }) {
  const [samples, setSamples] = useState<Sample[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    (async () => {
      try {
        const res = await fetch(`/api/metrics?days=${days}`);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const data = await res.json();
        if (active) setSamples(data.samples);
      } catch {
        if (active) setError("Couldn't load metrics.");
      }
    })();
    return () => {
      active = false;
    };
  }, [days]);

  const cards = useMemo(() => {
    if (!samples) return null;
    return METRICS.map((spec) => ({ spec, summary: summarize(spec, samples) }));
  }, [samples]);

  if (error) return <p className="text-alert text-sm">{error}</p>;

  if (!cards) {
    return (
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
        {METRICS.map((m) => (
          <div
            key={m.kind}
            className="border-border-hairline bg-fill-subtle h-28 animate-pulse rounded-[14px] border"
          />
        ))}
      </div>
    );
  }

  const hasAny = cards.some((c) => c.summary !== null);
  if (!hasAny) {
    return (
      <section className="border-border-strong rounded-[14px] border border-dashed p-8 text-center">
        <p className="text-text-secondary text-[15px]">
          Nothing synced yet. Pair your iPhone and let it sync to see your
          health data here.
        </p>
      </section>
    );
  }

  return (
    <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
      {cards.map(({ spec, summary }) => (
        <PulseCard key={spec.kind}>
          <div className="flex items-center gap-2">
            <span
              className="h-2.5 w-2.5 rounded-full"
              style={{ backgroundColor: spec.color }}
              aria-hidden
            />
            <PulseSectionLabel>{spec.label}</PulseSectionLabel>
          </div>
          {summary ? (
            <>
              <p className="text-text-primary mt-2 text-3xl font-semibold">
                {summary.display}
              </p>
              <p className="text-text-muted mt-1 text-sm">{summary.sub}</p>
            </>
          ) : (
            <p className="text-text-muted mt-2 text-[15px]">No data yet</p>
          )}
        </PulseCard>
      ))}
    </div>
  );
}
