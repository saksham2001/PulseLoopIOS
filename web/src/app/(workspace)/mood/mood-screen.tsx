"use client";

import { useMemo, useState } from "react";
import { PageHeader } from "@/components/ui";
import { useRecords } from "@/components/workspace/use-records";

interface MoodPayload {
  emoji?: string;
  label?: string;
}

const SCALE = [
  { emoji: "🔋", label: "Energized" },
  { emoji: "🙂", label: "Good" },
  { emoji: "😐", label: "Neutral" },
  { emoji: "😴", label: "Tired" },
  { emoji: "🪫", label: "Drained" },
];

function relWhen(iso: string): string {
  const d = new Date(iso);
  const mins = Math.round((Date.now() - d.getTime()) / 60000);
  if (mins < 60) return `${Math.max(1, mins)}m ago`;
  const hrs = Math.round(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  return d.toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

export function MoodScreen() {
  const mood = useRecords<MoodPayload>("mood");
  const [flash, setFlash] = useState(false);

  const recent = useMemo(
    () =>
      [...(mood.records ?? [])].sort(
        (a, b) => new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime(),
      ),
    [mood.records],
  );

  const checkIn = (s: (typeof SCALE)[number]) => {
    void mood.upsert({ emoji: s.emoji, label: s.label });
    setFlash(true);
    setTimeout(() => setFlash(false), 2000);
  };

  return (
    <div>
      <PageHeader title="Mood" subtitle="Quick daily check-in." />

      <div className="bg-background border-border-hairline mt-6 rounded-[16px] border p-[22px] shadow-sm">
        <div className="text-text-secondary mb-4 text-[15px] font-semibold">
          How&apos;s your energy right now?
        </div>
        <div className="flex flex-wrap gap-3">
          {SCALE.map((s) => (
            <button
              key={s.label}
              type="button"
              onClick={() => checkIn(s)}
              className="bg-fill-subtle hover:ring-accent flex flex-col items-center gap-1.5 rounded-[14px] px-5 py-3.5 hover:ring-2"
            >
              <span className="text-[28px]">{s.emoji}</span>
              <span className="text-[12.5px] font-medium">{s.label}</span>
            </button>
          ))}
        </div>
        {flash && (
          <div className="bg-success-bg text-success mt-3.5 inline-flex items-center gap-2 rounded-full px-3.5 py-2 text-[13.5px] font-semibold">
            ✓ Check-in saved
          </div>
        )}
      </div>

      <div className="text-text-muted mt-7 text-[11px] font-semibold tracking-[0.09em] uppercase">
        Recent check-ins
      </div>
      <div className="mt-3 flex flex-col gap-2.5">
        {!mood.loading && recent.length === 0 && (
          <div className="border-border-strong rounded-[16px] border border-dashed p-10 text-center">
            <p className="text-text-secondary text-[15px]">
              No check-ins yet. Tap an energy level above.
            </p>
          </div>
        )}
        {recent.map((m) => (
          <div
            key={m.clientId}
            className="bg-background border-border-hairline flex items-center gap-3 rounded-[14px] border px-[18px] py-3 shadow-sm"
          >
            <span className="text-[22px]">{m.payload.emoji ?? "🙂"}</span>
            <span className="flex-1 text-[15px] font-medium">
              {m.payload.label ?? "Check-in"}
            </span>
            <span className="text-text-muted text-[13px]">
              {relWhen(m.updatedAt)}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
