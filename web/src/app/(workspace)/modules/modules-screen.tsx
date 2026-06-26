"use client";

import { useMemo, useState } from "react";
import { PageHeader } from "@/components/ui";
import { Icons } from "@/components/workspace/icons";
import { useWorkspace } from "@/components/workspace/workspace-context";
import { MODULE_CATALOG, type ModuleDescriptor } from "@/lib/modules";
import type { ModuleId } from "@/lib/workspace";

export function ModulesScreen() {
  const { modules, toggleModule, isEnabled } = useWorkspace();
  const [detailId, setDetailId] = useState<ModuleId | null>(null);

  const enabled = useMemo(
    () => MODULE_CATALOG.filter((m) => modules[m.id]),
    [modules],
  );
  const available = useMemo(
    () => MODULE_CATALOG.filter((m) => !modules[m.id]),
    [modules],
  );

  if (detailId) {
    const mod = MODULE_CATALOG.find((m) => m.id === detailId);
    if (mod) {
      return (
        <ModuleDetail
          mod={mod}
          enabled={isEnabled(mod.id)}
          onToggle={() => toggleModule(mod.id)}
          onBack={() => setDetailId(null)}
        />
      );
    }
  }

  return (
    <div>
      <PageHeader
        title="Modules"
        subtitle="Enable or disable the building blocks of your workspace — your sidebar and feed update instantly."
      />

      <div className="text-text-muted mt-8 text-[11px] font-semibold tracking-[0.09em] uppercase">
        Enabled · {enabled.length} {enabled.length === 1 ? "module" : "modules"}
      </div>
      <div className="mt-3.5 grid grid-cols-2 gap-3.5">
        {enabled.map((m) => (
          <ModuleCard
            key={m.id}
            mod={m}
            enabled
            onToggle={() => toggleModule(m.id)}
            onOpen={() => setDetailId(m.id)}
          />
        ))}
      </div>

      {available.length > 0 && (
        <>
          <div className="text-text-muted mt-9 text-[11px] font-semibold tracking-[0.09em] uppercase">
            Available to add
          </div>
          <div className="mt-3.5 grid grid-cols-2 gap-3.5">
            {available.map((m) => (
              <ModuleCard
                key={m.id}
                mod={m}
                enabled={false}
                onToggle={() => toggleModule(m.id)}
                onOpen={() => setDetailId(m.id)}
              />
            ))}
          </div>
        </>
      )}
    </div>
  );
}

function ModuleCard({
  mod,
  enabled,
  onToggle,
  onOpen,
}: {
  mod: ModuleDescriptor;
  enabled: boolean;
  onToggle: () => void;
  onOpen: () => void;
}) {
  const Icon = Icons[mod.icon];
  return (
    <div className="bg-background border-border-hairline flex flex-col rounded-[16px] border p-[18px] shadow-sm">
      <button
        type="button"
        onClick={onOpen}
        className="flex items-start gap-3.5 text-left"
      >
        <div className="bg-fill-subtle text-text-primary flex h-11 w-11 shrink-0 items-center justify-center rounded-[12px]">
          <Icon />
        </div>
        <div className="min-w-0 flex-1">
          <div className="text-[15.5px] font-semibold">{mod.name}</div>
          <div className="text-text-muted mt-0.5 text-[13px] leading-[1.4]">
            {mod.summary}
          </div>
        </div>
      </button>
      <div className="mt-3.5 flex items-center justify-between">
        <span className="text-text-muted text-[12px]">
          v{mod.version} · {mod.author}
        </span>
        <button
          type="button"
          onClick={onToggle}
          className={
            enabled
              ? "border-border-strong text-text-secondary rounded-[10px] border px-3.5 py-[7px] text-[13px] font-semibold"
              : "bg-accent text-on-accent rounded-[10px] px-3.5 py-[7px] text-[13px] font-semibold"
          }
        >
          {enabled ? "Disable" : "Enable"}
        </button>
      </div>
    </div>
  );
}

function ModuleDetail({
  mod,
  enabled,
  onToggle,
  onBack,
}: {
  mod: ModuleDescriptor;
  enabled: boolean;
  onToggle: () => void;
  onBack: () => void;
}) {
  const Icon = Icons[mod.icon];
  return (
    <div>
      <button
        type="button"
        onClick={onBack}
        className="text-text-muted mb-5 text-[14px] font-medium"
      >
        ‹ All modules
      </button>

      <div className="flex items-start gap-4">
        <div className="bg-fill-subtle text-text-primary flex h-14 w-14 shrink-0 items-center justify-center rounded-[16px]">
          <Icon />
        </div>
        <div className="min-w-0 flex-1">
          <h1 className="text-text-primary m-0 font-serif text-[34px] leading-none font-normal tracking-tight">
            {mod.name}
          </h1>
          <p className="text-text-muted mt-2.5 max-w-[52ch] text-[15px] leading-[1.5]">
            {mod.description}
          </p>
          <div className="text-text-muted mt-2 text-[12.5px]">
            v{mod.version} · {mod.author}
          </div>
        </div>
        <button
          type="button"
          onClick={onToggle}
          className={
            enabled
              ? "border-border-strong text-text-secondary shrink-0 rounded-[11px] border px-4 py-2.5 text-[14px] font-semibold"
              : "bg-accent text-on-accent shrink-0 rounded-[11px] px-4 py-2.5 text-[14px] font-semibold"
          }
        >
          {enabled ? "Disable" : "Enable"}
        </button>
      </div>

      {mod.permissions.length > 0 && (
        <div className="mt-9">
          <div className="text-text-muted text-[11px] font-semibold tracking-[0.09em] uppercase">
            Permissions
          </div>
          <div className="border-border-hairline bg-background mt-3 overflow-hidden rounded-[14px] border">
            {mod.permissions.map((p, i) => (
              <div
                key={i}
                className="border-border-hairline flex items-center gap-3 border-b px-[18px] py-3.5 text-[14.5px] last:border-b-0"
              >
                <span className="text-text-muted">
                  <Icons.shield />
                </span>
                {p}
              </div>
            ))}
          </div>
        </div>
      )}

      <div className="mt-9">
        <div className="text-text-muted text-[11px] font-semibold tracking-[0.09em] uppercase">
          Changelog
        </div>
        <div className="mt-3 flex flex-col gap-3.5">
          {mod.changelog.map((c, i) => (
            <div
              key={i}
              className="border-border-hairline bg-background rounded-[14px] border p-[18px]"
            >
              <div className="text-[13px] font-semibold">
                v{c.version} · {c.date}
              </div>
              <div className="text-text-muted mt-1 text-[14px] leading-[1.45]">
                {c.notes}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
