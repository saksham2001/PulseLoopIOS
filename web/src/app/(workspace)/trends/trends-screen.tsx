"use client";

import { useEffect, useMemo, useState } from "react";
import { PageHeader } from "@/components/ui";
import { pulseSemantic } from "@/lib/tokens";

interface Sample {
  kind: string;
  value: number;
  unit: string | null;
  recordedAt: string;
}

const SERIES: { kind: string; label: string; color: string; unit: string }[] = [
  { kind: "heart_rate", label: "Heart rate", color: pulseSemantic.heartRate, unit: "bpm" },
  { kind: "spo2", label: "Blood oxygen", color: pulseSemantic.spo2, unit: "%" },
  { kind: "steps", label: "Steps", color: pulseSemantic.steps, unit: "" },
  { kind: "sleep_minutes", label: "Sleep", color: pulseSemantic.sleep, unit: "min" },
];

function Sparkline({ values, color }: { values: number[]; color: string }) {
  if (values.length < 2) {
    return <div className="bg-fill-subtle h-[44px] rounded-[8px]" />;
  }
  const min = Math.min(...values);
  const max = Math.max(...values);
  const range = max - min || 1;
  const w = 200;
  const h = 44;
  const pts = values
    .map((v, i) => {
      const x = (i / (values.length - 1)) * w;
      const y = h - ((v - min) / range) * h;
      return `${x.toFixed(1)},${y.toFixed(1)}`;
    })
    .join(" ");
  return (
    <svg
      viewBox={`0 0 ${w} ${h}`}
      preserveAspectRatio="none"
      className="h-[44px] w-full"
    >
      <polyline
        points={pts}
        fill="none"
        stroke={color}
        strokeWidth={2}
        strokeLinejoin="round"
        strokeLinecap="round"
        vectorEffect="non-scaling-stroke"
      />
    </svg>
  );
}

export function TrendsScreen() {
  const [samples, setSamples] = useState<Sample[] | null>(null);

  useEffect(() => {
    let active = true;
    (async () => {
      try {
        const res = await fetch("/api/metrics?days=14");
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

  const charts = useMemo(() => {
    const s = samples ?? [];
    return SERIES.map((spec) => {
      const mine = s
        .filter((x) => x.kind === spec.kind)
        .sort(
          (a, b) =>
            new Date(a.recordedAt).getTime() - new Date(b.recordedAt).getTime(),
        );
      const values = mine.map((x) => x.value);
      const latest = values.length ? values[values.length - 1] : null;
      return { spec, values, latest };
    });
  }, [samples]);

  const anyData = charts.some((c) => c.values.length > 0);

  return (
    <div>
      <PageHeader title="Insights" subtitle="Every metric, trended over time." />

      {samples && !anyData ? (
        <div className="border-border-strong mt-7 rounded-[16px] border border-dashed p-10 text-center">
          <p className="text-text-secondary text-[15px]">
            No metrics synced yet. Pair your iPhone to see trends here.
          </p>
        </div>
      ) : (
        <div className="mt-7 grid grid-cols-2 gap-3.5 max-[640px]:grid-cols-1">
          {charts.map(({ spec, values, latest }) => (
            <div
              key={spec.kind}
              className="bg-background border-border-hairline rounded-[16px] border p-[18px] shadow-sm"
            >
              <div className="flex items-baseline justify-between">
                <span className="text-text-muted text-[13px]">{spec.label}</span>
                <span className="text-[17px] font-bold tracking-tight">
                  {latest != null
                    ? `${Math.round(latest)}${spec.unit ? ` ${spec.unit}` : ""}`
                    : "—"}
                </span>
              </div>
              <div className="mt-3">
                <Sparkline values={values} color={spec.color} />
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
