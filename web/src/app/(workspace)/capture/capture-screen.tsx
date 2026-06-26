"use client";

import { useMemo, useState } from "react";
import { PageHeader } from "@/components/ui";
import { Icons, type IconName } from "@/components/workspace/icons";
import { useRecords } from "@/components/workspace/use-records";

interface CapturePayload {
  title?: string;
  sub?: string;
  icon?: IconName;
  target?: string; // record type to file into on accept
  action?: string; // e.g. "→ Tasks"
  status?: "pending" | "accepted" | "dismissed";
}

const ICON_FALLBACK: IconName = "spark";

export function CaptureScreen() {
  const captures = useRecords<CapturePayload>("capture");
  const tasks = useRecords("task");
  const notes = useRecords("note");
  const protocol = useRecords("medication");
  const meals = useRecords("meal");

  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [flash, setFlash] = useState<string | null>(null);

  const pending = useMemo(
    () => (captures.records ?? []).filter((r) => r.payload.status !== "accepted" && r.payload.status !== "dismissed"),
    [captures.records],
  );

  const flashMsg = (m: string) => {
    setFlash(m);
    setTimeout(() => setFlash(null), 2600);
  };

  const toggle = (id: string) =>
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });

  const selectAll = () =>
    setSelected((prev) =>
      prev.size === pending.length
        ? new Set()
        : new Set(pending.map((r) => r.clientId)),
    );

  const fileInto = (target: string, payload: CapturePayload) => {
    const data = { title: payload.title, label: "Captured" } as Record<string, unknown>;
    switch (target) {
      case "task":
        void tasks.upsert({ ...data, status: "todo" });
        break;
      case "note":
        void notes.upsert({ title: payload.title, body: payload.sub ?? "" });
        break;
      case "medication":
        void protocol.upsert({ name: payload.title, kind: "Supplement" });
        break;
      case "meal":
        void meals.upsert({ name: payload.title, kcal: 0 });
        break;
      default:
        void tasks.upsert({ ...data, status: "todo" });
    }
  };

  const acceptSelected = async () => {
    const chosen = pending.filter((r) => selected.has(r.clientId));
    for (const r of chosen) {
      fileInto(r.payload.target ?? "task", r.payload);
      await captures.upsert({ ...r.payload, status: "accepted" }, r.clientId);
    }
    flashMsg(`Filed ${chosen.length} ${chosen.length === 1 ? "item" : "items"}`);
    setSelected(new Set());
  };

  const dismissSelected = async () => {
    const chosen = pending.filter((r) => selected.has(r.clientId));
    for (const r of chosen) {
      await captures.upsert({ ...r.payload, status: "dismissed" }, r.clientId);
    }
    flashMsg(`Dismissed ${chosen.length} ${chosen.length === 1 ? "item" : "items"}`);
    setSelected(new Set());
  };

  const selectedCount = selected.size;

  return (
    <div>
      <PageHeader
        title="AI Capture"
        subtitle="Select multiple items and triage them in one pass — far faster than tapping one by one."
        action={
          <span className="bg-fill-subtle text-text-secondary inline-flex items-center gap-2 rounded-[11px] px-3.5 py-2 text-[13.5px] font-semibold">
            <Icons.spark />
            AI Triage
            <span className="bg-accent text-on-accent flex h-5 min-w-5 items-center justify-center rounded-[10px] px-1.5 text-[11px] font-bold">
              {pending.length}
            </span>
          </span>
        }
      />

      <div className="mt-7 flex items-center justify-between">
        <button
          type="button"
          onClick={selectAll}
          disabled={pending.length === 0}
          className="text-text-secondary text-[14px] font-semibold disabled:opacity-40"
        >
          {selected.size === pending.length && pending.length > 0
            ? "Deselect all"
            : "Select all"}
        </button>
        <span className="text-text-muted text-[13.5px]">
          Tip: click a row to select it.
        </span>
      </div>

      {flash && (
        <div className="bg-success-bg text-success mt-3 inline-flex items-center gap-2 rounded-full px-3.5 py-2 text-[13.5px] font-semibold">
          ✓ {flash}
        </div>
      )}

      <div className="mt-4 flex flex-col gap-2.5">
        {captures.loading && (
          <div className="text-text-muted py-10 text-center text-[15px]">
            Loading captures…
          </div>
        )}
        {!captures.loading && pending.length === 0 && (
          <div className="border-border-strong rounded-[16px] border border-dashed p-10 text-center">
            <p className="text-text-secondary text-[15px]">
              Inbox zero. New AI-suggested items will land here as you capture
              tasks, scan meals, or dictate notes.
            </p>
          </div>
        )}
        {pending.map((r) => {
          const Icon = Icons[r.payload.icon ?? ICON_FALLBACK] ?? Icons[ICON_FALLBACK];
          const isSel = selected.has(r.clientId);
          return (
            <button
              type="button"
              key={r.clientId}
              onClick={() => toggle(r.clientId)}
              className={`bg-background flex items-center gap-3.5 rounded-[14px] border px-[18px] py-[15px] text-left ${
                isSel ? "border-accent" : "border-border-hairline"
              }`}
            >
              <span
                className={`flex h-[22px] w-[22px] shrink-0 items-center justify-center rounded-[7px] border-2 text-[13px] font-bold ${
                  isSel
                    ? "bg-accent border-accent text-on-accent"
                    : "border-border-strong text-transparent"
                }`}
              >
                ✓
              </span>
              <div className="bg-fill-subtle text-text-primary flex h-[38px] w-[38px] shrink-0 items-center justify-center rounded-[10px]">
                <Icon />
              </div>
              <div className="min-w-0 flex-1">
                <div className="text-[15px] leading-[1.25] font-semibold">
                  {r.payload.title ?? "Captured item"}
                </div>
                {r.payload.sub && (
                  <div className="text-text-muted text-[13px]">
                    {r.payload.sub}
                  </div>
                )}
              </div>
              {r.payload.action && (
                <span className="text-text-muted shrink-0 text-[13px] font-medium">
                  {r.payload.action}
                </span>
              )}
            </button>
          );
        })}
      </div>

      {selectedCount > 0 && (
        <div className="border-border-strong bg-background shadow-[var(--shadow)] fixed bottom-6 left-1/2 z-40 flex -translate-x-1/2 items-center gap-3 rounded-[16px] border px-4 py-3">
          <span className="text-[14px] font-semibold">
            {selectedCount} selected
          </span>
          <button
            type="button"
            onClick={acceptSelected}
            className="bg-accent text-on-accent rounded-[11px] px-3.5 py-2 text-[13.5px] font-semibold"
          >
            Accept &amp; file
          </button>
          <button
            type="button"
            onClick={dismissSelected}
            className="border-border-strong text-text-secondary rounded-[11px] border px-3.5 py-2 text-[13.5px] font-semibold"
          >
            Dismiss
          </button>
          <button
            type="button"
            onClick={() => setSelected(new Set())}
            className="text-text-muted px-1 text-[16px]"
            aria-label="Clear selection"
          >
            ✕
          </button>
        </div>
      )}
    </div>
  );
}
