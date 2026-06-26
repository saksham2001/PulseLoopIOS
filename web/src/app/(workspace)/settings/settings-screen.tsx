"use client";

import Link from "next/link";
import { SignOutButton } from "@clerk/nextjs";
import { PageHeader } from "@/components/ui";
import { Icons, type IconName } from "@/components/workspace/icons";
import { useWorkspace } from "@/components/workspace/workspace-context";

const ROWS: { href: string; label: string; icon: IconName }[] = [
  { href: "/profile", label: "Profile", icon: "user" },
  { href: "/modules", label: "Modules", icon: "grid" },
  { href: "/connect", label: "Connect", icon: "link" },
  { href: "/permissions", label: "Privacy & permissions", icon: "shield" },
];

export function SettingsScreen() {
  const { theme, toggleTheme } = useWorkspace();
  const ThemeIcon = theme === "dark" ? Icons.sun : Icons.moon;

  return (
    <div>
      <PageHeader title="Settings" />

      <div className="text-text-muted mt-7 text-[11px] font-semibold tracking-[0.09em] uppercase">
        Appearance
      </div>
      <div className="bg-background border-border-hairline mt-3 flex items-center gap-4 rounded-[16px] border px-[18px] py-4 shadow-sm">
        <div className="min-w-0 flex-1">
          <div className="text-[15px] font-semibold">Theme</div>
          <div className="text-text-muted text-[13px]">Light or dark theme</div>
        </div>
        <button
          type="button"
          onClick={toggleTheme}
          className="border-border-strong text-text-secondary flex items-center gap-2 rounded-[10px] border px-3.5 py-2 text-[14px] font-semibold"
        >
          <ThemeIcon />
          {theme === "dark" ? "Dark" : "Light"}
        </button>
      </div>

      <div className="border-border-hairline bg-background mt-6 overflow-hidden rounded-[16px] border shadow-sm">
        {ROWS.map((r) => {
          const Icon = Icons[r.icon];
          return (
            <Link
              key={r.href}
              href={r.href}
              className="border-border-hairline flex items-center gap-3.5 border-b px-[18px] py-3.5 last:border-b-0"
            >
              <span className="text-text-muted">
                <Icon />
              </span>
              <span className="flex-1 text-[15px] font-medium">{r.label}</span>
              <span className="text-text-muted text-[16px]">›</span>
            </Link>
          );
        })}
      </div>

      <div className="mt-6">
        <SignOutButton>
          <button
            type="button"
            className="border-border-strong text-alert w-full rounded-[14px] border px-[18px] py-3.5 text-[15px] font-semibold"
          >
            Sign out
          </button>
        </SignOutButton>
      </div>

      <p className="text-text-muted mt-6 text-center text-[13px]">
        PulseLoop · v1.2.0
      </p>
    </div>
  );
}
