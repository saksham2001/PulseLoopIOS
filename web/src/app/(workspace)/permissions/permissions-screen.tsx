"use client";

import { PageHeader } from "@/components/ui";
import { useWorkspace } from "@/components/workspace/workspace-context";

export function PermissionsScreen() {
  const { permissions, setPermission } = useWorkspace();

  return (
    <div>
      <PageHeader
        title="Privacy & permissions"
        subtitle="You're in control of what PulseLoop can access."
      />

      <div className="border-border-hairline bg-background mt-7 overflow-hidden rounded-[16px] border shadow-sm">
        {permissions.map((p) => (
          <div
            key={p.id}
            className="border-border-hairline flex items-center gap-4 border-b px-[18px] py-4 last:border-b-0"
          >
            <div className="min-w-0 flex-1">
              <div className="text-[15px] font-semibold">{p.label}</div>
              <div className="text-text-muted text-[13px]">{p.detail}</div>
            </div>
            <button
              type="button"
              role="switch"
              aria-checked={p.on}
              onClick={() => setPermission(p.id, !p.on)}
              className={`relative h-[28px] w-[48px] shrink-0 rounded-full transition-colors ${
                p.on ? "bg-accent" : "bg-fill-subtle border-border-strong border"
              }`}
            >
              <span
                className={`absolute top-[3px] h-[22px] w-[22px] rounded-full bg-white shadow transition-all ${
                  p.on ? "left-[23px]" : "left-[3px]"
                }`}
              />
            </button>
          </div>
        ))}
      </div>

      <p className="text-text-muted mt-4 text-[13.5px]">
        Changes save automatically and sync to your account.
      </p>
    </div>
  );
}
