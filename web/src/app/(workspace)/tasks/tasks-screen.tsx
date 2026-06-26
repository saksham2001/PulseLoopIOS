"use client";

import { useMemo, useState } from "react";
import { PageHeader } from "@/components/ui";
import { useRecords, type SyncRecord } from "@/components/workspace/use-records";

interface TaskPayload {
  title?: string;
  status?: string;
  label?: string;
  order?: number;
}

const COLUMNS: { id: string; title: string }[] = [
  { id: "todo", title: "To do" },
  { id: "in_progress", title: "Doing" },
  { id: "done", title: "Done" },
];

export function TasksScreen() {
  const tasks = useRecords<TaskPayload>("task");
  const [dragId, setDragId] = useState<string | null>(null);
  const [overCol, setOverCol] = useState<string | null>(null);

  const byColumn = useMemo(() => {
    const map: Record<string, SyncRecord<TaskPayload>[]> = {
      todo: [],
      in_progress: [],
      done: [],
    };
    for (const r of tasks.records ?? []) {
      const s = r.payload.status ?? "todo";
      const col = s === "done" || s === "cancelled" ? "done" : s === "in_progress" ? "in_progress" : "todo";
      map[col].push(r);
    }
    for (const c of Object.keys(map)) {
      map[c].sort((a, b) => (a.payload.order ?? 0) - (b.payload.order ?? 0));
    }
    return map;
  }, [tasks.records]);

  const moveTo = (clientId: string, status: string) => {
    const rec = (tasks.records ?? []).find((r) => r.clientId === clientId);
    if (!rec || rec.payload.status === status) return;
    void tasks.upsert({ ...rec.payload, status }, clientId);
  };

  const addTo = (status: string, title: string) => {
    const t = title.trim();
    if (!t) return;
    void tasks.upsert({ title: t, status, label: "Today" });
  };

  return (
    <div>
      <PageHeader
        title="Tasks"
        subtitle="Drag cards between columns · type in any column to add."
      />

      <div className="mt-7 grid grid-cols-3 gap-4 max-[820px]:grid-cols-1">
        {COLUMNS.map((col) => {
          const list = byColumn[col.id];
          const isOver = overCol === col.id;
          return (
            <div
              key={col.id}
              onDragOver={(e) => {
                e.preventDefault();
                if (overCol !== col.id) setOverCol(col.id);
              }}
              onDrop={(e) => {
                e.preventDefault();
                if (dragId) moveTo(dragId, col.id);
                setDragId(null);
                setOverCol(null);
              }}
              className={`bg-fill-subtle/40 flex flex-col gap-2.5 rounded-[16px] border p-3.5 ${
                isOver ? "border-accent" : "border-border-hairline"
              }`}
            >
              <div className="flex items-center justify-between px-1">
                <span className="text-[14px] font-semibold">{col.title}</span>
                <span className="text-text-muted text-[12.5px] font-semibold">
                  {list.length}
                </span>
              </div>

              {list.map((t) => {
                const done = col.id === "done";
                return (
                  <div
                    key={t.clientId}
                    draggable
                    onDragStart={() => setDragId(t.clientId)}
                    onDragEnd={() => {
                      setDragId(null);
                      setOverCol(null);
                    }}
                    className={`bg-background border-border-hairline flex items-center gap-2.5 rounded-[12px] border px-3.5 py-3 shadow-sm ${
                      dragId === t.clientId ? "opacity-40" : ""
                    }`}
                  >
                    <button
                      type="button"
                      onClick={() =>
                        moveTo(t.clientId, done ? "todo" : "done")
                      }
                      className={`flex h-5 w-5 shrink-0 items-center justify-center rounded-full border-2 text-[11px] ${
                        done
                          ? "bg-accent border-accent text-on-accent"
                          : "border-border-strong text-transparent"
                      }`}
                      aria-label={done ? "Mark as to do" : "Mark as done"}
                    >
                      ✓
                    </button>
                    <span
                      className={`flex-1 cursor-grab text-[14.5px] ${
                        done ? "text-text-muted line-through" : "font-medium"
                      }`}
                    >
                      {t.payload.title || "Untitled"}
                    </span>
                    {t.payload.label && (
                      <span className="bg-fill-subtle text-text-secondary rounded-[7px] px-2 py-0.5 text-[11.5px] font-semibold">
                        {t.payload.label}
                      </span>
                    )}
                  </div>
                );
              })}

              <input
                onKeyDown={(e) => {
                  if (e.key === "Enter" && e.currentTarget.value.trim()) {
                    addTo(col.id, e.currentTarget.value);
                    e.currentTarget.value = "";
                  }
                }}
                placeholder="+ Add…"
                className="bg-transparent px-1 py-1.5 text-[14px] outline-none"
              />
            </div>
          );
        })}
      </div>
    </div>
  );
}
