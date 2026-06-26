"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Icons, type IconName } from "./icons";
import { useWorkspace } from "./workspace-context";
import { usePalette } from "./command-palette";
import type { ModuleId } from "@/lib/workspace";

interface NavItem {
  href: string;
  label: string;
  icon: IconName;
  module?: ModuleId;
  badge?: string;
}

interface NavGroup {
  label?: string;
  items: NavItem[];
}

// Sidebar structure ported from the prototype's `nav` builder. Items whose
// `module` is disabled are hidden; a group with no surviving items collapses.
const NAV: NavGroup[] = [
  {
    items: [
      { href: "/home", label: "Home", icon: "home" },
      { href: "/today", label: "Today's plan", icon: "calCheck", module: "day_plan" },
      { href: "/capture", label: "AI Capture", icon: "inbox", module: "ai_capture" },
    ],
  },
  {
    label: "Collections",
    items: [
      { href: "/notes", label: "Notes", icon: "doc", module: "notes" },
      { href: "/tasks", label: "Tasks", icon: "check", module: "tasks" },
      { href: "/protocol", label: "Protocol", icon: "pill", module: "protocol" },
      { href: "/journal", label: "Journal", icon: "book", module: "journal" },
    ],
  },
  {
    label: "Health",
    items: [
      { href: "/tracker", label: "Tracker", icon: "chart" },
      { href: "/sleep", label: "Sleep", icon: "moon", module: "sleep" },
      { href: "/fitness", label: "Fitness", icon: "dumbbell", module: "workouts" },
      { href: "/nutrition", label: "Nutrition", icon: "fork", module: "nutrition" },
      { href: "/mood", label: "Mood", icon: "smile", module: "mood" },
    ],
  },
  {
    label: "Insights",
    items: [
      { href: "/insights", label: "AI Insights", icon: "spark" },
      { href: "/trends", label: "Insights", icon: "trend" },
    ],
  },
  {
    label: "You",
    items: [
      { href: "/travel", label: "Travel", icon: "plane", module: "travel" },
      { href: "/accountability", label: "Accountability", icon: "flame", module: "accountability" },
      { href: "/profile", label: "Profile", icon: "user" },
    ],
  },
  {
    label: "Settings",
    items: [
      { href: "/modules", label: "Modules", icon: "grid" },
      { href: "/connect", label: "Connect", icon: "link" },
      { href: "/permissions", label: "Privacy & permissions", icon: "shield" },
      { href: "/settings", label: "Settings", icon: "gear" },
    ],
  },
];

export function Sidebar({ captureCount }: { captureCount?: number }) {
  const pathname = usePathname();
  const { isEnabled, theme, toggleTheme } = useWorkspace();
  const { open: openPalette } = usePalette();

  const ThemeIcon = theme === "dark" ? Icons.sun : Icons.moon;

  return (
    <aside className="border-border-hairline bg-background flex w-[268px] shrink-0 flex-col gap-0.5 overflow-y-auto border-r px-3.5 py-[18px]">
      <div className="flex items-center gap-[11px] px-2 pt-2 pb-3.5">
        <div className="bg-accent text-on-accent flex h-10 w-10 shrink-0 items-center justify-center rounded-[11px] text-[17px] font-bold">
          R
        </div>
        <div className="min-w-0 leading-tight">
          <div className="text-[15px] font-bold">Rey&apos;s Brain</div>
          <div className="text-text-muted text-[12.5px]">Personal workspace</div>
        </div>
        <div className="text-text-muted ml-auto text-[16px]">⌄</div>
      </div>

      <button
        type="button"
        onClick={openPalette}
        className="bg-fill-subtle border-border-hairline text-text-secondary mx-1 mb-2.5 flex items-center gap-[9px] rounded-[11px] border px-3 py-[9px] text-left"
      >
        <span className="flex w-4">
          <Icons.search />
        </span>
        <span className="text-[13.5px]">Quick add or search</span>
        <span className="border-border-strong text-text-muted ml-auto rounded-[6px] border px-1.5 py-0.5 text-[11px] font-semibold">
          ⌘K
        </span>
      </button>

      <nav className="flex flex-col gap-0.5">
        {NAV.map((group, gi) => {
          const visible = group.items.filter(
            (it) => !it.module || isEnabled(it.module),
          );
          if (visible.length === 0) return null;
          return (
            <div key={group.label ?? gi} className="flex flex-col gap-0.5">
              {group.label && (
                <div className="text-text-muted px-2 pt-3.5 pb-[5px] text-[11px] font-semibold tracking-[0.09em] uppercase">
                  {group.label}
                </div>
              )}
              {visible.map((it) => {
                const active =
                  pathname === it.href || pathname.startsWith(`${it.href}/`);
                const Icon = Icons[it.icon];
                const badge =
                  it.href === "/capture" && captureCount
                    ? String(captureCount)
                    : it.badge;
                return (
                  <Link
                    key={it.href}
                    href={it.href}
                    className={`text-text-primary flex items-center gap-[11px] rounded-[10px] px-2.5 py-[9px] ${
                      active ? "bg-fill-subtle font-semibold" : "font-medium"
                    }`}
                  >
                    <span className="flex w-5 shrink-0 justify-center">
                      <Icon />
                    </span>
                    <span className="text-[14.5px]">{it.label}</span>
                    {badge && (
                      <span className="bg-accent text-on-accent ml-auto flex h-5 min-w-5 items-center justify-center rounded-[10px] px-1.5 text-[11px] font-bold">
                        {badge}
                      </span>
                    )}
                  </Link>
                );
              })}
            </div>
          );
        })}
      </nav>

      <div className="mt-auto pt-3.5">
        <button
          type="button"
          onClick={toggleTheme}
          className="border-border-hairline text-text-secondary flex w-full items-center gap-2.5 rounded-[10px] border px-2.5 py-[9px]"
        >
          <span className="flex w-5 justify-center">
            <ThemeIcon />
          </span>
          <span className="text-[14px] font-medium">
            {theme === "dark" ? "Light mode" : "Dark mode"}
          </span>
        </button>
      </div>
    </aside>
  );
}
