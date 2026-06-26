"use client";

import { useEffect, useMemo, useState } from "react";
import { PageHeader } from "@/components/ui";
import { Icons } from "@/components/workspace/icons";

interface Sample {
  kind: string;
  value: number;
  recordedAt: string;
}

const DEFAULT_TEMPLATES = [
  { name: "Push day", detail: "Chest · shoulders · triceps · 6 exercises" },
  { name: "Pull day", detail: "Back · biceps · 5 exercises" },
  { name: "Legs", detail: "Quads · hamstrings · calves · 6 exercises" },
  { name: "Zone 2 cardio", detail: "45 min · steady state" },
];

function startOfDay(d: Date) {
  const x = new Date(d);
  x.setHours(0, 0, 0, 0);
  return x.getTime();
}

export function FitnessScreen() {
  const [samples, setSamples] = useState<Sample[] | null>(null);

  useEffect(() => {
    let active = true;
    (async () => {
      try {
        const res = await fetch("/api/metrics?days=30");
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

  const cards = useMemo(() => {
    const s = samples ?? [];
    const todayStart = startOfDay(new Date());
    const stepsToday = s
      .filter((x) => x.kind === "steps" && new Date(x.recordedAt).getTime() >= todayStart)
      .reduce((a, x) => a + x.value, 0);
    const activeDays = new Set(
      s
        .filter((x) => x.kind === "active_energy" || x.kind === "steps")
        .map((x) => startOfDay(new Date(x.recordedAt))),
    ).size;
    const workouts = s.filter((x) => x.kind === "workout_minutes").length;
    return [
      { label: "Steps today", value: stepsToday ? Math.round(stepsToday).toLocaleString() : "—", unit: "" },
      { label: "Active days", value: activeDays ? String(activeDays) : "—", unit: "/ 30" },
      { label: "Workouts", value: workouts ? String(workouts) : "—", unit: "logged" },
    ];
  }, [samples]);

  return (
    <div>
      <PageHeader title="Fitness" subtitle="Last 30 days." />

      <div className="text-text-muted mt-7 text-[11px] font-semibold tracking-[0.09em] uppercase">
        Activity
      </div>
      <div className="mt-3 grid grid-cols-3 gap-3.5 max-[640px]:grid-cols-1">
        {cards.map((c) => (
          <div
            key={c.label}
            className="bg-background border-border-hairline rounded-[16px] border p-[18px] shadow-sm"
          >
            <div className="text-text-muted text-[13px]">{c.label}</div>
            <div className="mt-1 text-[28px] font-bold tracking-tight">
              {c.value}
              {c.unit && (
                <span className="text-text-muted text-[13px] font-medium">
                  {" "}
                  {c.unit}
                </span>
              )}
            </div>
          </div>
        ))}
      </div>

      <div className="text-text-muted mt-9 text-[11px] font-semibold tracking-[0.09em] uppercase">
        Workout templates
      </div>
      <div className="mt-3 flex flex-col gap-2.5">
        {DEFAULT_TEMPLATES.map((t) => (
          <div
            key={t.name}
            className="bg-background border-border-hairline flex items-center gap-3.5 rounded-[14px] border px-[18px] py-3.5 shadow-sm"
          >
            <div className="bg-fill-subtle text-text-primary flex h-[40px] w-[40px] shrink-0 items-center justify-center rounded-[11px]">
              <Icons.dumbbell />
            </div>
            <div className="min-w-0 flex-1">
              <div className="text-[15px] font-semibold">{t.name}</div>
              <div className="text-text-muted text-[13px]">{t.detail}</div>
            </div>
            <button
              type="button"
              className="border-border-strong text-text-secondary shrink-0 rounded-[10px] border px-3.5 py-2 text-[13.5px] font-semibold"
            >
              Start
            </button>
          </div>
        ))}
      </div>
    </div>
  );
}
