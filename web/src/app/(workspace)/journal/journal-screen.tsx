"use client";

import { useMemo, useState } from "react";
import { PageHeader } from "@/components/ui";
import { useRecords } from "@/components/workspace/use-records";

interface JournalPayload {
  emoji?: string;
  body?: string;
}

const MOODS = ["😄", "🙂", "😐", "😕", "😣"];

function relWhen(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleDateString(undefined, {
    weekday: "short",
    month: "short",
    day: "numeric",
  });
}

export function JournalScreen() {
  const journal = useRecords<JournalPayload>("journal");
  const [emoji, setEmoji] = useState("🙂");
  const [draft, setDraft] = useState("");

  const sorted = useMemo(
    () =>
      [...(journal.records ?? [])].sort(
        (a, b) => new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime(),
      ),
    [journal.records],
  );

  const save = () => {
    const body = draft.trim();
    if (!body) return;
    void journal.upsert({ emoji, body });
    setDraft("");
  };

  return (
    <div>
      <PageHeader title="Journal" />

      <div className="bg-background border-border-hairline mt-6 rounded-[16px] border p-[18px] shadow-sm">
        <div className="text-text-secondary mb-3 text-[14px] font-semibold">
          How are you feeling?
        </div>
        <div className="mb-3 flex gap-2">
          {MOODS.map((m) => (
            <button
              key={m}
              type="button"
              onClick={() => setEmoji(m)}
              className={`flex h-11 w-11 items-center justify-center rounded-[12px] text-[22px] ${
                emoji === m
                  ? "bg-accent/10 ring-accent ring-2"
                  : "bg-fill-subtle"
              }`}
            >
              {m}
            </button>
          ))}
        </div>
        <textarea
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          placeholder="Write about your day…"
          className="border-border-strong min-h-[96px] w-full resize-none rounded-[12px] border bg-transparent px-3.5 py-3 text-[15px] leading-[1.5] outline-none"
        />
        <div className="mt-3 flex justify-end">
          <button
            type="button"
            onClick={save}
            disabled={!draft.trim()}
            className="bg-accent text-on-accent rounded-[11px] px-4 py-2.5 text-[14px] font-semibold disabled:opacity-40"
          >
            Save entry
          </button>
        </div>
      </div>

      <div className="mt-5 flex flex-col gap-3">
        {journal.loading && (
          <div className="text-text-muted py-8 text-center text-[15px]">
            Loading entries…
          </div>
        )}
        {!journal.loading && sorted.length === 0 && (
          <div className="border-border-strong rounded-[16px] border border-dashed p-10 text-center">
            <p className="text-text-secondary text-[15px]">
              No journal entries yet. Capture how you&apos;re feeling above.
            </p>
          </div>
        )}
        {sorted.map((j) => (
          <div
            key={j.clientId}
            className="bg-background border-border-hairline rounded-[16px] border p-[18px] shadow-sm"
          >
            <div className="mb-2 flex items-center gap-2.5">
              <span className="text-[22px]">{j.payload.emoji ?? "🙂"}</span>
              <span className="text-text-muted text-[13px]">
                {relWhen(j.updatedAt)}
              </span>
              <button
                type="button"
                onClick={() => journal.remove(j.clientId)}
                className="text-text-muted ml-auto px-1 text-[14px]"
                aria-label="Delete entry"
              >
                ✕
              </button>
            </div>
            <p className="text-[15px] leading-[1.55] whitespace-pre-wrap">
              {j.payload.body}
            </p>
          </div>
        ))}
      </div>
    </div>
  );
}
