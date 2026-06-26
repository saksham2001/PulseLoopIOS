"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { PageHeader } from "@/components/ui";
import { Icons } from "@/components/workspace/icons";
import { useRecords, type SyncRecord } from "@/components/workspace/use-records";

interface NotePayload {
  title?: string;
  body?: string;
}

function relWhen(iso: string): string {
  const d = new Date(iso);
  const days = Math.floor((Date.now() - d.getTime()) / 86400000);
  if (days <= 0) return "Today";
  if (days === 1) return "Yesterday";
  if (days < 7) return `${days}d ago`;
  return d.toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

function preview(body: string): string {
  return body.replace(/\s+/g, " ").trim().slice(0, 120);
}

export function NotesScreen() {
  const notes = useRecords<NotePayload>("note");
  const [openId, setOpenId] = useState<string | null>(null);
  const [query, setQuery] = useState("");

  const sorted = useMemo(
    () =>
      [...(notes.records ?? [])].sort(
        (a, b) => new Date(b.updatedAt).getTime() - new Date(a.updatedAt).getTime(),
      ),
    [notes.records],
  );

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return sorted;
    return sorted.filter(
      (n) =>
        (n.payload.title ?? "").toLowerCase().includes(q) ||
        (n.payload.body ?? "").toLowerCase().includes(q),
    );
  }, [sorted, query]);

  const open = sorted.find((n) => n.clientId === openId) ?? null;

  if (open) {
    return (
      <NoteEditor
        note={open}
        onBack={() => setOpenId(null)}
        onSave={(payload) => notes.upsert(payload, open.clientId)}
      />
    );
  }

  return (
    <div>
      <PageHeader
        title="Notes"
        action={
          <button
            type="button"
            onClick={async () => {
              const created = await notes.upsert({ title: "Untitled note", body: "" });
              setOpenId(created.clientId);
            }}
            className="bg-accent text-on-accent inline-flex items-center gap-1.5 rounded-[11px] px-4 py-2.5 text-[14px] font-semibold"
          >
            <span className="text-[16px]">＋</span> New note
          </button>
        }
      />

      <div className="border-border-strong bg-background mt-6 flex items-center gap-2.5 rounded-[12px] border px-3.5 py-2.5">
        <span className="text-text-muted">
          <Icons.search />
        </span>
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search notes…"
          className="flex-1 bg-transparent text-[14.5px] outline-none"
        />
      </div>

      <div className="mt-4 grid grid-cols-2 gap-3.5 max-[760px]:grid-cols-1">
        {notes.loading && (
          <div className="text-text-muted col-span-2 py-10 text-center text-[15px]">
            Loading notes…
          </div>
        )}
        {!notes.loading && filtered.length === 0 && (
          <div className="border-border-strong col-span-2 rounded-[16px] border border-dashed p-10 text-center">
            <p className="text-text-secondary text-[15px]">
              {query ? "No notes match your search." : "No notes yet. Create your first note."}
            </p>
          </div>
        )}
        {filtered.map((n) => (
          <button
            type="button"
            key={n.clientId}
            onClick={() => setOpenId(n.clientId)}
            className="bg-background border-border-hairline rounded-[16px] border p-[18px] text-left shadow-sm"
          >
            <div className="flex items-start justify-between gap-3">
              <span className="text-[15.5px] font-semibold">
                {n.payload.title || "Untitled note"}
              </span>
              <span className="text-text-muted shrink-0 text-[12.5px]">
                {relWhen(n.updatedAt)}
              </span>
            </div>
            <p className="text-text-muted mt-1.5 text-[13.5px] leading-[1.45]">
              {preview(n.payload.body ?? "") || "No content yet"}
            </p>
          </button>
        ))}
      </div>
    </div>
  );
}

function NoteEditor({
  note,
  onBack,
  onSave,
}: {
  note: SyncRecord<NotePayload>;
  onBack: () => void;
  onSave: (payload: NotePayload) => void;
}) {
  const [title, setTitle] = useState(note.payload.title ?? "");
  const [body, setBody] = useState(note.payload.body ?? "");
  const lastSaved = useRef({ title: note.payload.title ?? "", body: note.payload.body ?? "" });

  const words = body.trim() ? body.trim().split(/\s+/).length : 0;
  const chars = body.length;

  // Commit on blur (and on unmount) if changed — persists via the records API.
  const commit = () => {
    if (title === lastSaved.current.title && body === lastSaved.current.body) return;
    lastSaved.current = { title, body };
    onSave({ title, body });
  };
  useEffect(() => {
    return () => {
      if (title !== lastSaved.current.title || body !== lastSaved.current.body) {
        onSave({ title, body });
      }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [title, body]);

  return (
    <div>
      <button
        type="button"
        onClick={() => {
          commit();
          onBack();
        }}
        className="text-text-muted mb-4 text-[14px] font-medium"
      >
        ‹ Back to Notes
      </button>

      <div className="text-text-muted mb-3 flex items-center gap-2 text-[12.5px]">
        <span>Notes › {title || "Untitled note"}</span>
        <span>·</span>
        <span>
          {words} words · {chars} characters · saved
        </span>
      </div>

      <input
        value={title}
        onChange={(e) => setTitle(e.target.value)}
        onBlur={commit}
        placeholder="Untitled note"
        className="w-full bg-transparent font-serif text-[34px] leading-tight font-normal tracking-tight outline-none"
      />

      <div className="text-text-muted mt-4 mb-3 flex items-center gap-3 text-[13px]">
        <span className="bg-fill-subtle text-text-secondary inline-flex items-center gap-1.5 rounded-[9px] px-2.5 py-1.5 font-semibold">
          <Icons.spark /> AI Summary
        </span>
        <span>
          Type below and PulseLoop keeps a running summary. Use the toolbar to
          extract tasks or link notes.
        </span>
      </div>

      <textarea
        value={body}
        onChange={(e) => setBody(e.target.value)}
        onBlur={commit}
        placeholder="Start writing…"
        className="min-h-[44vh] w-full resize-none bg-transparent text-[16px] leading-[1.6] outline-none"
      />
    </div>
  );
}
