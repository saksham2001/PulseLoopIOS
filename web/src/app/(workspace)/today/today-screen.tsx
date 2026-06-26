"use client";

import { useMemo } from "react";
import { PageHeader } from "@/components/ui";
import { Icons } from "@/components/workspace/icons";
import { useRecords } from "@/components/workspace/use-records";

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

interface ScheduleBlock {
  time: string;
  icon: React.ReactNode;
  title: string;
  note: string;
}

function relativeWhen(iso: string): string {
  const then = new Date(iso).getTime();
  const mins = Math.round((Date.now() - then) / 60000);
  if (mins < 1) return "just now";
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.round(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  return `${Math.round(hrs / 24)}d ago`;
}

export function TodayScreen() {
  const tasks = useRecords<TaskPayload>("task");
  const protocol = useRecords<ProtocolPayload>("medication");

  // Schedule is drafted from real protocol timing + open tasks. Where the
  // prototype shows fixed anchor blocks (wake / focus / wind-down) we keep them
  // as a calm scaffold the agent fills around.
  // TODO: real agent-drafted schedule once the planner endpoint exists.
  const schedule = useMemo<ScheduleBlock[]>(() => {
    const blocks: ScheduleBlock[] = [];
    const proto = protocol.records ?? [];
    const morning = proto.filter(
      (p) => (p.payload.timing ?? "").toLowerCase().includes("morning"),
    );
    const evening = proto.filter((p) =>
      ["evening", "bed", "night"].some((k) =>
        (p.payload.timing ?? "").toLowerCase().includes(k),
      ),
    );
    const openTasks = (tasks.records ?? []).filter(
      (t) => t.payload.status !== "done",
    );

    blocks.push({
      time: "7:00",
      icon: <Icons.sun />,
      title: "Morning routine",
      note: morning.length
        ? morning.map((p) => p.payload.name).join(" · ")
        : "Hydrate, sunlight, protocol",
    });
    if (openTasks[0]) {
      blocks.push({
        time: "9:30",
        icon: <Icons.check />,
        title: openTasks[0].payload.title ?? "Deep work",
        note: "Highest-leverage task first",
      });
    }
    blocks.push({
      time: "13:00",
      icon: <Icons.fork />,
      title: "Lunch & reset",
      note: "Protein-forward, short walk",
    });
    if (openTasks[1]) {
      blocks.push({
        time: "15:00",
        icon: <Icons.check />,
        title: openTasks[1].payload.title ?? "Afternoon block",
        note: "Second focus session",
      });
    }
    blocks.push({
      time: "21:30",
      icon: <Icons.moon />,
      title: "Wind down",
      note: evening.length
        ? evening.map((p) => p.payload.name).join(" · ")
        : "Screens off, evening protocol",
    });
    return blocks;
  }, [protocol.records, tasks.records]);

  // Agent action log = the most recent real record mutations across modules.
  const agentActions = useMemo(() => {
    const all = [
      ...(tasks.records ?? []).map((r) => ({
        icon: <Icons.check />,
        text: `Filed task “${r.payload.title ?? "Untitled"}”`,
        at: r.updatedAt,
      })),
      ...(protocol.records ?? []).map((r) => ({
        icon: <Icons.pill />,
        text: `Logged ${r.payload.name ?? "protocol item"} to your protocol`,
        at: r.updatedAt,
      })),
    ];
    return all
      .sort((a, b) => new Date(b.at).getTime() - new Date(a.at).getTime())
      .slice(0, 6);
  }, [tasks.records, protocol.records]);

  return (
    <div>
      <PageHeader
        title="Today's plan"
        subtitle="AI-drafted from your tasks, protocol & habits."
      />

      <div className="mt-8 grid grid-cols-[1.6fr_1fr] items-start gap-5 max-[900px]:grid-cols-1">
        <section className="bg-background border-border-hairline rounded-[16px] border p-[22px] shadow-sm">
          <div className="text-text-muted mb-4 text-[11px] font-semibold tracking-[0.09em] uppercase">
            Schedule
          </div>
          <div className="flex flex-col">
            {schedule.map((b, i) => (
              <div
                key={i}
                className="border-border-hairline flex items-start gap-4 border-b py-3.5 last:border-b-0"
              >
                <span className="text-text-muted w-[46px] shrink-0 pt-0.5 text-[14px] font-semibold tabular-nums">
                  {b.time}
                </span>
                <div className="bg-fill-subtle text-text-primary flex h-[38px] w-[38px] shrink-0 items-center justify-center rounded-[10px]">
                  {b.icon}
                </div>
                <div className="min-w-0">
                  <div className="text-[15px] leading-[1.25] font-semibold">
                    {b.title}
                  </div>
                  <div className="text-text-muted text-[13px]">{b.note}</div>
                </div>
              </div>
            ))}
          </div>
        </section>

        <section className="bg-background border-border-hairline rounded-[16px] border p-[22px] shadow-sm">
          <div className="text-text-muted mb-4 text-[11px] font-semibold tracking-[0.09em] uppercase">
            Agent actions · today
          </div>
          {agentActions.length === 0 ? (
            <p className="text-text-muted text-[14px]">
              No agent activity yet today. As you capture tasks and log protocol
              items, they&apos;ll appear here.
            </p>
          ) : (
            <div className="flex flex-col gap-3.5">
              {agentActions.map((a, i) => (
                <div key={i} className="flex items-start gap-3">
                  <span className="text-text-muted mt-0.5 shrink-0">
                    {a.icon}
                  </span>
                  <span className="flex-1 text-[14px] leading-[1.4]">
                    {a.text}
                  </span>
                  <span className="text-text-muted shrink-0 text-[12.5px]">
                    {relativeWhen(a.at)}
                  </span>
                </div>
              ))}
            </div>
          )}
        </section>
      </div>
    </div>
  );
}
