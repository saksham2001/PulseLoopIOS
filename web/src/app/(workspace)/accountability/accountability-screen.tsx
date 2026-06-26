"use client";

import { useMemo, useState } from "react";
import { PageHeader } from "@/components/ui";
import { useRecords } from "@/components/workspace/use-records";

interface QuitPayload {
  emoji?: string;
  name?: string;
  startedAt?: string;
  bestDays?: number;
  savedPerDay?: number;
}

// No social graph backend yet — friends are a static, clearly-marked stub.
// TODO: real friends source once accountability/social sync lands.
const FRIENDS = [
  { initial: "M", name: "Maya", streak: 42 },
  { initial: "J", name: "Jordan", streak: 18 },
  { initial: "S", name: "Sam", streak: 7 },
];

function daysSince(iso?: string): number {
  if (!iso) return 0;
  const start = new Date(iso).getTime();
  if (Number.isNaN(start)) return 0;
  return Math.max(0, Math.floor((Date.now() - start) / 86400000));
}

export function AccountabilityScreen() {
  const quit = useRecords<QuitPayload>("quit_program");
  const [name, setName] = useState("");

  const programs = useMemo(() => quit.records ?? [], [quit.records]);

  const add = () => {
    const n = name.trim();
    if (!n) return;
    void quit.upsert({
      emoji: "🚭",
      name: n,
      startedAt: new Date().toISOString(),
      bestDays: 0,
      savedPerDay: 0,
    });
    setName("");
  };

  return (
    <div>
      <PageHeader
        title="Accountability"
        subtitle="Streaks, quit programs & people keeping you honest."
      />

      <div className="border-border-strong bg-background mt-7 flex items-center gap-2.5 rounded-[14px] border px-3.5 py-2.5">
        <input
          value={name}
          onChange={(e) => setName(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && add()}
          placeholder="Start a quit program (e.g. Nicotine)…"
          className="flex-1 bg-transparent text-[15px] outline-none"
        />
        <button
          type="button"
          onClick={add}
          className="bg-accent text-on-accent rounded-[10px] px-4 py-2 text-[14px] font-semibold"
        >
          Start
        </button>
      </div>

      <div className="mt-4 grid grid-cols-2 gap-3.5 max-[640px]:grid-cols-1">
        {programs.map((q) => {
          const streak = daysSince(q.payload.startedAt);
          const saved = (q.payload.savedPerDay ?? 0) * streak;
          const best = Math.max(q.payload.bestDays ?? 0, streak);
          return (
            <div
              key={q.clientId}
              className="bg-background border-border-hairline rounded-[16px] border p-[22px] shadow-sm"
            >
              <div className="flex items-center gap-2.5">
                <span className="text-[26px]">{q.payload.emoji ?? "🚭"}</span>
                <span className="text-[16px] font-semibold">
                  {q.payload.name}
                </span>
                <button
                  type="button"
                  onClick={() => quit.remove(q.clientId)}
                  className="text-text-muted ml-auto px-1 text-[15px]"
                  aria-label="Remove program"
                >
                  ✕
                </button>
              </div>
              <div className="mt-3 font-serif text-[40px] leading-none">
                {streak}
              </div>
              <div className="text-text-muted text-[13.5px]">
                days clean · {q.payload.name}
              </div>
              <div className="mt-3.5 grid grid-cols-2 gap-3">
                <div className="bg-fill-subtle rounded-[10px] px-3 py-2">
                  <div className="text-[17px] font-bold">
                    ${Math.round(saved)}
                  </div>
                  <div className="text-text-muted text-[12px]">Saved</div>
                </div>
                <div className="bg-fill-subtle rounded-[10px] px-3 py-2">
                  <div className="text-[17px] font-bold">{best}</div>
                  <div className="text-text-muted text-[12px]">Best</div>
                </div>
              </div>
            </div>
          );
        })}
        {!quit.loading && programs.length === 0 && (
          <div className="border-border-strong col-span-2 rounded-[16px] border border-dashed p-10 text-center">
            <p className="text-text-secondary text-[15px]">
              No quit programs yet. Start one above to begin a streak.
            </p>
          </div>
        )}
      </div>

      <div className="text-text-muted mt-9 text-[11px] font-semibold tracking-[0.09em] uppercase">
        Friends
      </div>
      <div className="mt-3 flex flex-col gap-2.5">
        {FRIENDS.map((f) => (
          <div
            key={f.name}
            className="bg-background border-border-hairline flex items-center gap-3.5 rounded-[14px] border px-[18px] py-3.5 shadow-sm"
          >
            <div className="bg-fill-subtle text-text-primary flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-[15px] font-bold">
              {f.initial}
            </div>
            <span className="flex-1 text-[15px] font-semibold">{f.name}</span>
            <span className="text-text-secondary text-[14px] font-semibold">
              🔥 {f.streak}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
