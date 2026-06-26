"use client";

import { useUser } from "@clerk/nextjs";
import { PageHeader } from "@/components/ui";
import { Icons } from "@/components/workspace/icons";
import { useRecords } from "@/components/workspace/use-records";

export function ProfileScreen() {
  const { user } = useUser();
  const tasks = useRecords("task");
  const notes = useRecords("note");
  const journal = useRecords("journal");

  const firstName =
    user?.firstName ?? user?.username ?? user?.fullName ?? "You";
  const initial = firstName.charAt(0).toUpperCase();
  const memberSince = user?.createdAt
    ? new Date(user.createdAt).getFullYear()
    : new Date().getFullYear();

  const doneTasks = (tasks.records ?? []).filter(
    (r) => (r.payload as { status?: string }).status === "done",
  ).length;

  const stats = [
    { value: String(doneTasks), label: "Tasks done" },
    { value: String((notes.records ?? []).length), label: "Notes" },
    { value: String((journal.records ?? []).length), label: "Journal entries" },
  ];

  const goals = [
    { emoji: "💪", text: "Train 4× per week" },
    { emoji: "😴", text: "7.5h sleep average" },
    { emoji: "🧘", text: "Daily mindfulness check-in" },
  ];

  return (
    <div>
      <div className="flex items-center gap-4">
        <div className="bg-accent text-on-accent flex h-16 w-16 shrink-0 items-center justify-center rounded-[18px] text-[26px] font-bold">
          {initial}
        </div>
        <div>
          <PageHeader
            title={firstName}
            subtitle={`Personal workspace · member since ${memberSince}`}
          />
        </div>
      </div>

      <div className="mt-7 grid grid-cols-3 gap-3.5 max-[560px]:grid-cols-1">
        {stats.map((s) => (
          <div
            key={s.label}
            className="bg-background border-border-hairline rounded-[16px] border p-[18px] text-center shadow-sm"
          >
            <div className="text-[28px] font-bold tracking-tight">
              {s.value}
            </div>
            <div className="text-text-muted text-[13px]">{s.label}</div>
          </div>
        ))}
      </div>

      <div className="text-text-muted mt-9 text-[11px] font-semibold tracking-[0.09em] uppercase">
        Goals
      </div>
      <div className="mt-3 flex flex-col gap-2.5">
        {goals.map((g) => (
          <div
            key={g.text}
            className="bg-background border-border-hairline flex items-center gap-3.5 rounded-[14px] border px-[18px] py-3.5 shadow-sm"
          >
            <span className="text-[20px]">{g.emoji}</span>
            <span className="flex-1 text-[15px] font-medium">{g.text}</span>
            <span className="text-text-muted">
              <Icons.spark />
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}
