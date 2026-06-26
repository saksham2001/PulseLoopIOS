"use client";

import { useMemo, useState } from "react";
import { useWorkspace } from "@/components/workspace/workspace-context";
import { useRecords } from "@/components/workspace/use-records";
import { Icons } from "@/components/workspace/icons";
import {
  HOME_SECTION_META,
  type HomeSection,
  type ModuleId,
} from "@/lib/workspace";

interface TaskPayload {
  title?: string;
  status?: string;
  label?: string;
}
interface ProtocolPayload {
  name?: string;
  kind?: string;
  dose?: string;
  timing?: string;
}

const ALL_SECTION_IDS = Object.keys(HOME_SECTION_META);

function todayGreeting(): string {
  const h = new Date().getHours();
  if (h < 5) return "Good night, Rey";
  if (h < 12) return "Good morning, Rey";
  if (h < 18) return "Good afternoon, Rey";
  return "Good evening, Rey";
}

function dateLine(): string {
  return new Date().toLocaleDateString(undefined, {
    weekday: "long",
    month: "long",
    day: "numeric",
  });
}

export function HomeScreen() {
  const { homeLayout, setHomeLayout, isEnabled } = useWorkspace();
  const tasks = useRecords<TaskPayload>("task");
  const protocol = useRecords<ProtocolPayload>("medication");

  const [editing, setEditing] = useState(false);
  const [flash, setFlash] = useState<string | null>(null);
  const [dragId, setDragId] = useState<string | null>(null);
  const [overId, setOverId] = useState<string | null>(null);

  // Sections gated by a disabled module drop out (prototype `secModule`).
  const sectionModule: Record<string, ModuleId | undefined> = {
    tasks: "tasks",
    protocol: "protocol",
  };
  const visible = homeLayout.filter((s) => {
    const m = sectionModule[s.id];
    return !m || isEnabled(m);
  });

  const library = ALL_SECTION_IDS.filter(
    (id) =>
      !homeLayout.some((s) => s.id === id) &&
      (!sectionModule[id] || isEnabled(sectionModule[id]!)),
  );

  const openTasks = useMemo(
    () =>
      (tasks.records ?? [])
        .filter((r) => r.payload.status !== "done")
        .slice(0, 4),
    [tasks.records],
  );

  const flashMsg = (m: string) => {
    setFlash(m);
    setTimeout(() => setFlash(null), 2600);
  };

  const quickAdd = async (value: string) => {
    const title = value.trim();
    if (!title) return;
    await tasks.upsert({ title, status: "todo", label: "Today" });
    flashMsg(`“${title}” added to Tasks`);
  };

  const move = (id: string, dir: -1 | 1) => {
    const o = [...homeLayout];
    const i = o.findIndex((s) => s.id === id);
    const j = i + dir;
    if (j < 0 || j >= o.length) return;
    [o[i], o[j]] = [o[j], o[i]];
    setHomeLayout(o);
  };
  const reorder = (from: string, to: string) => {
    const o = [...homeLayout];
    const i = o.findIndex((s) => s.id === from);
    const j = o.findIndex((s) => s.id === to);
    if (i < 0 || j < 0 || i === j) return;
    const [moved] = o.splice(i, 1);
    o.splice(j, 0, moved);
    setHomeLayout(o);
  };
  const toggleSpan = (id: string) =>
    setHomeLayout(
      homeLayout.map((s) =>
        s.id === id ? { ...s, span: s.span === 2 ? 1 : 2 } : s,
      ),
    );
  const removeSection = (id: string) =>
    setHomeLayout(homeLayout.filter((s) => s.id !== id));
  const addSection = (id: string) =>
    setHomeLayout([
      ...homeLayout,
      { id, span: HOME_SECTION_META[id].defaultSpan } as HomeSection,
    ]);

  return (
    <div>
      <div className="flex items-start justify-between gap-6">
        <div>
          <div className="text-text-muted mb-1.5 text-[15px]">{dateLine()}</div>
          <h1 className="text-text-primary m-0 font-serif text-[46px] leading-[1.04] font-normal tracking-tight">
            {todayGreeting()}
          </h1>
        </div>
        <div
          className="shadow-[var(--shadow)] h-[108px] w-[108px] shrink-0 rounded-[20px] bg-cover bg-center"
          style={{
            backgroundImage:
              "url('https://images.unsplash.com/photo-1502082553048-f009c37129b9?w=400&q=80')",
          }}
        />
      </div>

      <div className="bg-background border-border-strong mt-6 flex items-center gap-3 rounded-[16px] border px-[18px] py-3.5 shadow-sm">
        <span className="text-text-primary">
          <Icons.spark />
        </span>
        <input
          onKeyDown={(e) => {
            if (e.key === "Enter") {
              void quickAdd(e.currentTarget.value);
              e.currentTarget.value = "";
            }
          }}
          placeholder="Capture a task, log a meal, or ask AI…  (Enter to add)"
          className="flex-1 bg-transparent py-0.5 text-[16px] outline-none"
        />
        <span className="border-border-strong text-text-muted rounded-[6px] border px-[7px] py-[3px] text-[11px] font-semibold">
          Enter ↵
        </span>
      </div>

      {flash && (
        <div className="bg-success-bg text-success mt-2.5 inline-flex items-center gap-2 rounded-full px-3.5 py-2 text-[13.5px] font-semibold">
          ✓ {flash}
        </div>
      )}

      <div className="mt-7 flex items-center justify-between">
        <span className="text-text-muted text-[15px]">A calm daily feed</span>
        <button
          type="button"
          onClick={() => setEditing((v) => !v)}
          className="border-border-strong bg-background text-text-primary rounded-[11px] border px-[18px] py-2 text-[14px] font-semibold"
        >
          {editing ? "Done" : "Customize"}
        </button>
      </div>

      {editing ? (
        <div className="mt-[18px] flex flex-col gap-2.5">
          {visible.map((s) => {
            const meta = HOME_SECTION_META[s.id];
            const isOver = overId === s.id && dragId && dragId !== s.id;
            return (
              <div
                key={s.id}
                draggable
                onDragStart={() => setDragId(s.id)}
                onDragOver={(e) => {
                  e.preventDefault();
                  if (overId !== s.id) setOverId(s.id);
                }}
                onDrop={(e) => {
                  e.preventDefault();
                  if (dragId) reorder(dragId, s.id);
                  setDragId(null);
                  setOverId(null);
                }}
                onDragEnd={() => {
                  setDragId(null);
                  setOverId(null);
                }}
                className={`bg-background flex items-center gap-3.5 rounded-[14px] border px-[18px] py-[15px] ${
                  isOver ? "border-accent" : "border-border-hairline"
                } ${dragId === s.id ? "opacity-40" : "opacity-100"}`}
              >
                <span className="text-text-muted cursor-grab text-[18px]">≡</span>
                <span className="text-[16px] font-semibold">{meta.title}</span>
                <div className="ml-auto flex gap-2">
                  <button
                    type="button"
                    onClick={() => toggleSpan(s.id)}
                    className="bg-fill-subtle text-text-secondary flex h-[38px] w-[38px] items-center justify-center rounded-[10px] text-[13px] font-semibold"
                  >
                    {s.span === 2 ? "1×" : "2×"}
                  </button>
                  <button
                    type="button"
                    onClick={() => move(s.id, -1)}
                    className="bg-fill-subtle text-text-secondary flex h-[38px] w-[38px] items-center justify-center rounded-[10px]"
                  >
                    ↑
                  </button>
                  <button
                    type="button"
                    onClick={() => move(s.id, 1)}
                    className="bg-fill-subtle text-text-secondary flex h-[38px] w-[38px] items-center justify-center rounded-[10px]"
                  >
                    ↓
                  </button>
                  <button
                    type="button"
                    onClick={() => removeSection(s.id)}
                    className="bg-fill-subtle text-text-secondary flex h-[38px] w-[38px] items-center justify-center rounded-[10px]"
                  >
                    ✕
                  </button>
                </div>
              </div>
            );
          })}
          {library.length > 0 && (
            <>
              <div className="text-text-muted mt-2 text-[11px] font-semibold tracking-[0.09em] uppercase">
                Add a module
              </div>
              <div className="flex flex-wrap gap-2.5">
                {library.map((id) => (
                  <button
                    type="button"
                    key={id}
                    onClick={() => addSection(id)}
                    className="border-border-strong bg-background text-text-secondary flex items-center gap-2 rounded-[11px] border border-dashed px-3.5 py-[9px] text-[14px] font-medium"
                  >
                    <span className="text-[16px]">＋</span>
                    {HOME_SECTION_META[id].title}
                  </button>
                ))}
              </div>
            </>
          )}
        </div>
      ) : (
        <div className="mt-5 grid grid-cols-2 items-start gap-4">
          {visible.map((s) => {
            const meta = HOME_SECTION_META[s.id];
            return (
              <div
                key={s.id}
                className="bg-background border-border-hairline rounded-[16px] border p-[22px] shadow-sm"
                style={{ gridColumn: `span ${s.span}` }}
              >
                <div className="mb-3.5 flex items-center justify-between">
                  <span className="text-text-muted text-[11px] font-semibold tracking-[0.09em] uppercase">
                    {meta.title}
                  </span>
                  {meta.meta && (
                    <span className="text-text-muted text-[13px]">
                      {meta.meta}
                    </span>
                  )}
                </div>
                <SectionBody
                  id={s.id}
                  openTasks={openTasks}
                  protocol={protocol.records ?? []}
                  onToggleTask={(r) =>
                    tasks.upsert(
                      {
                        ...r.payload,
                        status: r.payload.status === "done" ? "todo" : "done",
                      },
                      r.clientId,
                    )
                  }
                  onAddTask={(t) => tasks.upsert({ title: t, status: "todo", label: "Today" })}
                />
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

function SectionBody({
  id,
  openTasks,
  protocol,
  onToggleTask,
  onAddTask,
}: {
  id: string;
  openTasks: { clientId: string; payload: TaskPayload }[];
  protocol: { clientId: string; payload: ProtocolPayload }[];
  onToggleTask: (r: { clientId: string; payload: TaskPayload }) => void;
  onAddTask: (title: string) => void;
}) {
  if (id === "upnext") {
    const items = [
      {
        when: "Morning",
        icon: <Icons.pill />,
        title: "BPC-157 · Creatine · Omega-3",
        sub: "Medication & supplements",
      },
      {
        when: "Today",
        icon: <Icons.check />,
        title: openTasks[0]?.payload.title ?? "Draft Q3 strategy outline",
        sub: "Work",
      },
      {
        when: "Evening",
        icon: <Icons.syringe />,
        title: "Ipamorelin · 200 mcg",
        sub: "Peptide · before bed",
      },
    ];
    return (
      <div className="flex flex-col">
        {items.map((u, i) => (
          <div
            key={i}
            className="border-border-hairline flex items-center gap-3.5 border-b py-3 last:border-b-0"
          >
            <span className="text-text-muted w-[58px] shrink-0 text-[13px]">
              {u.when}
            </span>
            <div className="bg-fill-subtle flex h-[38px] w-[38px] shrink-0 items-center justify-center rounded-[10px]">
              {u.icon}
            </div>
            <div className="min-w-0">
              <div className="text-[15px] leading-[1.25] font-semibold">
                {u.title}
              </div>
              <div className="text-text-muted text-[13px]">{u.sub}</div>
            </div>
          </div>
        ))}
      </div>
    );
  }

  if (id === "tasks") {
    return (
      <div className="flex flex-col">
        {openTasks.map((t) => (
          <div
            key={t.clientId}
            className="border-border-hairline flex items-center gap-3 border-b py-[11px]"
          >
            <button
              type="button"
              onClick={() => onToggleTask(t)}
              className="border-border-strong flex h-6 w-6 shrink-0 items-center justify-center rounded-full border-2"
            />
            <span className="flex-1 text-[15px] font-medium">
              {t.payload.title}
            </span>
            <span
              className={`rounded-[7px] px-2.5 py-1 text-[12px] font-semibold ${
                t.payload.label === "Today"
                  ? "bg-alert-bg text-alert"
                  : "bg-fill-subtle text-text-secondary"
              }`}
            >
              {t.payload.label ?? "Today"}
            </span>
          </div>
        ))}
        <input
          onKeyDown={(e) => {
            if (e.key === "Enter" && e.currentTarget.value.trim()) {
              onAddTask(e.currentTarget.value.trim());
              e.currentTarget.value = "";
            }
          }}
          placeholder="+ Add task…"
          className="bg-transparent pt-3 pb-0.5 text-[14.5px] outline-none"
        />
      </div>
    );
  }

  if (id === "rightnow") {
    return (
      <div className="bg-fill-subtle rounded-[12px] p-[18px]">
        <div className="mb-2 flex items-center gap-2">
          <span className="bg-accent h-[7px] w-[7px] rounded-full" />
          <span className="text-text-muted text-[11px] font-semibold tracking-[0.09em] uppercase">
            Just this one thing
          </span>
        </div>
        <div className="font-serif text-[21px] leading-[1.3]">
          {openTasks[0]?.payload.title
            ? `${openTasks[0].payload.title}.`
            : "Draft the Q3 strategy outline before your 2pm."}
        </div>
      </div>
    );
  }

  if (id === "aidigest") {
    return (
      <div className="font-serif text-[18px] leading-[1.45]">
        Sleep held at 7h21m and resting HR is down 3bpm this week. Good window to
        push the harder workout you skipped Monday.
      </div>
    );
  }

  if (id === "protocol") {
    const items =
      protocol.length > 0
        ? protocol.slice(0, 3).map((p) => ({
            icon:
              p.payload.kind === "Peptide" ? <Icons.syringe /> : <Icons.pill />,
            name: p.payload.name ?? "Item",
            sub: `${p.payload.kind ?? "Supplement"}${
              p.payload.timing ? ` · ${p.payload.timing}` : ""
            }`,
            dose: p.payload.dose ?? "—",
          }))
        : [
            { icon: <Icons.syringe />, name: "BPC-157", sub: "Peptide · morning", dose: "250 mcg" },
            { icon: <Icons.pill />, name: "Creatine", sub: "Supplement · daily", dose: "5 g" },
            { icon: <Icons.syringe />, name: "Ipamorelin", sub: "Peptide · before bed", dose: "200 mcg" },
          ];
    return (
      <div className="flex flex-col gap-3">
        {items.map((p, i) => (
          <div key={i} className="flex items-center gap-3">
            <div className="bg-fill-subtle flex h-[34px] w-[34px] shrink-0 items-center justify-center rounded-[9px]">
              {p.icon}
            </div>
            <div className="min-w-0 flex-1">
              <div className="text-[14.5px] font-semibold">{p.name}</div>
              <div className="text-text-muted text-[12.5px]">{p.sub}</div>
            </div>
            <span className="text-text-muted text-[12.5px]">{p.dose}</span>
          </div>
        ))}
      </div>
    );
  }

  if (id === "vitals") {
    const vitals = [
      { label: "Heart rate", value: "74", unit: "bpm", bg: "linear-gradient(90deg,rgba(180,69,58,.18),rgba(180,69,58,.04))" },
      { label: "Blood oxygen", value: "97", unit: "%", bg: "linear-gradient(90deg,rgba(74,127,181,.18),rgba(74,127,181,.04))" },
      { label: "Sleep", value: "7h21", unit: "", bg: "linear-gradient(90deg,rgba(107,95,160,.18),rgba(107,95,160,.04))" },
    ];
    return (
      <div className="flex flex-wrap gap-3.5">
        {vitals.map((v) => (
          <div key={v.label} className="min-w-[120px] flex-1">
            <div className="text-text-muted mb-0.5 text-[13px]">{v.label}</div>
            <div className="text-[26px] font-bold tracking-tight">
              {v.value}
              <span className="text-text-muted text-[13px] font-medium">
                {" "}
                {v.unit}
              </span>
            </div>
            <div
              className="mt-2 h-[34px] rounded-[7px]"
              style={{ background: v.bg }}
            />
          </div>
        ))}
      </div>
    );
  }

  return null;
}
