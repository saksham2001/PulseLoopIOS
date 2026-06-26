"use client";

import { useEffect, useMemo, useState } from "react";
import {
  Area,
  AreaChart,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { PulseCard } from "@/components/ui";
import { pulseSemantic } from "@/lib/tokens";

interface Sample {
  id: string;
  kind: string;
  value: number;
  unit: string | null;
  recordedAt: string;
}

const KIND_LABELS: Record<string, string> = {
  heart_rate: "Heart rate",
  spo2: "Blood oxygen",
  steps: "Steps",
  sleep_minutes: "Sleep",
};

// Per-metric color, mirroring iOS PulseColors health-metric palette.
const KIND_COLORS: Record<string, string> = {
  heart_rate: pulseSemantic.heartRate,
  spo2: pulseSemantic.spo2,
  steps: pulseSemantic.steps,
  sleep_minutes: pulseSemantic.sleep,
};

function label(kind: string) {
  return KIND_LABELS[kind] ?? kind.replace(/_/g, " ");
}

function color(kind: string) {
  return KIND_COLORS[kind] ?? pulseSemantic.spo2;
}

export function MetricsPanel() {
  const [samples, setSamples] = useState<Sample[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    (async () => {
      try {
        const res = await fetch("/api/metrics?days=30");
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
  }, []);

  const byKind = useMemo(() => {
    const map = new Map<string, Sample[]>();
    for (const s of samples ?? []) {
      const list = map.get(s.kind) ?? [];
      list.push(s);
      map.set(s.kind, list);
    }
    return map;
  }, [samples]);

  if (error) {
    return <p className="text-alert text-sm">{error}</p>;
  }

  if (!samples) {
    return (
      <div className="border-border-hairline bg-fill-subtle h-40 animate-pulse rounded-[14px] border" />
    );
  }

  if (samples.length === 0) {
    return (
      <section className="border-border-strong rounded-[14px] border border-dashed p-8 text-center">
        <p className="text-text-secondary text-[15px]">
          No metrics yet. Pair your iPhone and let it sync.
        </p>
      </section>
    );
  }

  return (
    <div className="space-y-4">
      {[...byKind.entries()].map(([kind, list]) => {
        const sorted = [...list].sort(
          (a, b) =>
            new Date(a.recordedAt).getTime() - new Date(b.recordedAt).getTime(),
        );
        const latest = sorted[sorted.length - 1];
        const chartData = sorted.map((s) => ({
          t: new Date(s.recordedAt).getTime(),
          value: s.value,
        }));
        const stroke = color(kind);

        return (
          <PulseCard key={kind}>
            <div className="flex items-baseline justify-between">
              <h3 className="text-text-secondary text-sm font-medium">
                {label(kind)}
              </h3>
              <p className="text-text-primary text-2xl font-semibold">
                {Math.round(latest.value * 10) / 10}
                {latest.unit ? (
                  <span className="text-text-muted ml-1 text-sm font-normal">
                    {latest.unit}
                  </span>
                ) : null}
              </p>
            </div>

            <div className="mt-4 h-32">
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={chartData}>
                  <defs>
                    <linearGradient id={`g-${kind}`} x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor={stroke} stopOpacity={0.4} />
                      <stop offset="100%" stopColor={stroke} stopOpacity={0} />
                    </linearGradient>
                  </defs>
                  <XAxis
                    dataKey="t"
                    type="number"
                    domain={["dataMin", "dataMax"]}
                    tickFormatter={(t) =>
                      new Date(t).toLocaleDateString(undefined, {
                        month: "short",
                        day: "numeric",
                      })
                    }
                    stroke="#9a9a98"
                    fontSize={11}
                  />
                  <YAxis stroke="#9a9a98" fontSize={11} width={28} />
                  <Tooltip
                    contentStyle={{
                      background: "#ffffff",
                      border: "1px solid #ececec",
                      borderRadius: 12,
                      fontSize: 12,
                      color: "#1b1b1a",
                    }}
                    labelFormatter={(t) => new Date(t).toLocaleString()}
                  />
                  <Area
                    type="monotone"
                    dataKey="value"
                    stroke={stroke}
                    fill={`url(#g-${kind})`}
                    strokeWidth={2}
                  />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          </PulseCard>
        );
      })}
    </div>
  );
}
