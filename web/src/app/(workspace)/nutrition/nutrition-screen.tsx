"use client";

import { useMemo, useState } from "react";
import { PageHeader } from "@/components/ui";
import { useRecords } from "@/components/workspace/use-records";

interface MealPayload {
  name?: string;
  kcal?: number;
  protein?: number;
  carbs?: number;
  fat?: number;
  emoji?: string;
  loggedAt?: string;
}

function startOfToday() {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}

export function NutritionScreen() {
  const meals = useRecords<MealPayload>("meal");
  const [name, setName] = useState("");
  const [kcal, setKcal] = useState("");

  const today = useMemo(
    () =>
      (meals.records ?? [])
        .filter((m) => new Date(m.updatedAt).getTime() >= startOfToday())
        .sort(
          (a, b) =>
            new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime(),
        ),
    [meals.records],
  );

  const totals = useMemo(() => {
    return today.reduce(
      (acc, m) => ({
        kcal: acc.kcal + (m.payload.kcal ?? 0),
        protein: acc.protein + (m.payload.protein ?? 0),
        carbs: acc.carbs + (m.payload.carbs ?? 0),
        fat: acc.fat + (m.payload.fat ?? 0),
      }),
      { kcal: 0, protein: 0, carbs: 0, fat: 0 },
    );
  }, [today]);

  const add = () => {
    const n = name.trim();
    if (!n) return;
    void meals.upsert({
      name: n,
      kcal: Number(kcal) || 0,
      emoji: "🍽️",
      loggedAt: new Date().toISOString(),
    });
    setName("");
    setKcal("");
  };

  const macros = [
    { label: "Protein", value: Math.round(totals.protein) },
    { label: "Carbs", value: Math.round(totals.carbs) },
    { label: "Fat", value: Math.round(totals.fat) },
  ];

  return (
    <div>
      <PageHeader
        title="Nutrition"
        subtitle={`Today · ${Math.round(totals.kcal).toLocaleString()} kcal logged.`}
      />

      <div className="mt-7 grid grid-cols-3 gap-3.5 max-[640px]:grid-cols-1">
        {macros.map((m) => (
          <div
            key={m.label}
            className="bg-background border-border-hairline rounded-[16px] border p-[18px] shadow-sm"
          >
            <div className="text-text-muted text-[13px]">{m.label}</div>
            <div className="mt-1 text-[26px] font-bold tracking-tight">
              {m.value}
              <span className="text-text-muted text-[13px] font-medium">g</span>
            </div>
          </div>
        ))}
      </div>

      <div className="border-border-strong bg-background mt-5 flex items-center gap-2.5 rounded-[14px] border px-3.5 py-2.5">
        <input
          value={name}
          onChange={(e) => setName(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && add()}
          placeholder="Log a meal…"
          className="flex-1 bg-transparent text-[15px] outline-none"
        />
        <input
          value={kcal}
          onChange={(e) => setKcal(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && add()}
          placeholder="kcal"
          inputMode="numeric"
          className="w-[72px] bg-transparent text-right text-[15px] outline-none"
        />
        <button
          type="button"
          onClick={add}
          className="border-border-strong text-text-muted rounded-[8px] border px-2.5 py-1.5 text-[11px] font-semibold"
        >
          Enter ↵
        </button>
      </div>

      <div className="mt-4 flex flex-col gap-2.5">
        {meals.loading && (
          <div className="text-text-muted py-8 text-center text-[15px]">
            Loading meals…
          </div>
        )}
        {!meals.loading && today.length === 0 && (
          <div className="border-border-strong rounded-[16px] border border-dashed p-10 text-center">
            <p className="text-text-secondary text-[15px]">
              No meals logged today yet.
            </p>
          </div>
        )}
        {today.map((m) => (
          <div
            key={m.clientId}
            className="bg-background border-border-hairline flex items-center gap-3.5 rounded-[14px] border px-[18px] py-3.5 shadow-sm"
          >
            <span className="text-[22px]">{m.payload.emoji ?? "🍽️"}</span>
            <div className="min-w-0 flex-1">
              <div className="text-[15px] font-semibold">{m.payload.name}</div>
              <div className="text-text-muted text-[13px]">
                {new Date(m.updatedAt).toLocaleTimeString([], {
                  hour: "numeric",
                  minute: "2-digit",
                })}
              </div>
            </div>
            <span className="text-text-secondary shrink-0 text-[14px] font-semibold">
              {m.payload.kcal ?? 0} kcal
            </span>
            <button
              type="button"
              onClick={() => meals.remove(m.clientId)}
              className="text-text-muted shrink-0 px-1 text-[15px]"
              aria-label="Remove meal"
            >
              ✕
            </button>
          </div>
        ))}
      </div>
    </div>
  );
}
