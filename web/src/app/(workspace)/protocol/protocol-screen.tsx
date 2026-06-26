"use client";

import { useState } from "react";
import { PageHeader } from "@/components/ui";
import { Icons } from "@/components/workspace/icons";
import { useRecords } from "@/components/workspace/use-records";

interface ProtocolPayload {
  name?: string;
  kind?: string;
  dose?: string;
  timing?: string;
}

const KINDS = ["Supplement", "Peptide", "Medication"] as const;

export function ProtocolScreen() {
  const protocol = useRecords<ProtocolPayload>("medication");
  const [kind, setKind] = useState<(typeof KINDS)[number]>("Supplement");
  const [name, setName] = useState("");
  const [dose, setDose] = useState("");
  const [timing, setTiming] = useState("");

  const add = () => {
    const n = name.trim();
    if (!n) return;
    void protocol.upsert({
      name: n,
      kind,
      dose: dose.trim() || undefined,
      timing: timing.trim() || undefined,
    });
    setName("");
    setDose("");
    setTiming("");
  };

  return (
    <div>
      <PageHeader
        title="Protocol"
        subtitle="Add supplements, medications & peptides with full dosing."
      />

      <div className="bg-background border-border-hairline mt-7 rounded-[16px] border p-[18px] shadow-sm">
        <div className="text-text-muted mb-3 text-[11px] font-semibold tracking-[0.09em] uppercase">
          Add to protocol
        </div>
        <div className="flex flex-wrap items-end gap-2.5">
          <div className="flex gap-1.5">
            {KINDS.map((k) => (
              <button
                key={k}
                type="button"
                onClick={() => setKind(k)}
                className={`rounded-[10px] px-3 py-2 text-[13.5px] font-semibold ${
                  kind === k
                    ? "bg-accent text-on-accent"
                    : "bg-fill-subtle text-text-secondary"
                }`}
              >
                {k}
              </button>
            ))}
          </div>
          <input
            value={name}
            onChange={(e) => setName(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && add()}
            placeholder="Name"
            className="border-border-strong min-w-[160px] flex-1 rounded-[10px] border bg-transparent px-3 py-2 text-[14.5px] outline-none"
          />
          <input
            value={dose}
            onChange={(e) => setDose(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && add()}
            placeholder="Dose (e.g. 5 g)"
            className="border-border-strong w-[130px] rounded-[10px] border bg-transparent px-3 py-2 text-[14.5px] outline-none"
          />
          <input
            value={timing}
            onChange={(e) => setTiming(e.target.value)}
            onKeyDown={(e) => e.key === "Enter" && add()}
            placeholder="Timing (e.g. morning)"
            className="border-border-strong w-[150px] rounded-[10px] border bg-transparent px-3 py-2 text-[14.5px] outline-none"
          />
          <button
            type="button"
            onClick={add}
            className="bg-accent text-on-accent rounded-[10px] px-4 py-2 text-[14px] font-semibold"
          >
            Add
          </button>
        </div>
      </div>

      <div className="mt-4 flex flex-col gap-2.5">
        {protocol.loading && (
          <div className="text-text-muted py-10 text-center text-[15px]">
            Loading protocol…
          </div>
        )}
        {!protocol.loading && (protocol.records ?? []).length === 0 && (
          <div className="border-border-strong rounded-[16px] border border-dashed p-10 text-center">
            <p className="text-text-secondary text-[15px]">
              Nothing in your protocol yet. Add your first item above.
            </p>
          </div>
        )}
        {(protocol.records ?? []).map((p) => {
          const isPeptide = p.payload.kind === "Peptide";
          return (
            <div
              key={p.clientId}
              className="bg-background border-border-hairline flex items-center gap-3.5 rounded-[14px] border px-[18px] py-3.5 shadow-sm"
            >
              <div className="bg-fill-subtle text-text-primary flex h-[40px] w-[40px] shrink-0 items-center justify-center rounded-[11px]">
                {isPeptide ? <Icons.syringe /> : <Icons.pill />}
              </div>
              <div className="min-w-0 flex-1">
                <div className="text-[15px] font-semibold">
                  {p.payload.name}
                </div>
                <div className="text-text-muted text-[13px]">
                  {p.payload.kind ?? "Supplement"}
                  {p.payload.timing ? ` · ${p.payload.timing}` : ""}
                </div>
              </div>
              {p.payload.dose && (
                <span className="text-text-secondary shrink-0 text-[14px] font-semibold">
                  {p.payload.dose}
                </span>
              )}
              <button
                type="button"
                onClick={() => protocol.remove(p.clientId)}
                className="text-text-muted shrink-0 px-1 text-[15px]"
                aria-label="Remove"
              >
                ✕
              </button>
            </div>
          );
        })}
      </div>
    </div>
  );
}
