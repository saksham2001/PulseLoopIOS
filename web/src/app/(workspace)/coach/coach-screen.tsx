"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { Icons } from "@/components/workspace/icons";
import { useWorkspace } from "@/components/workspace/workspace-context";
import type { ModuleId } from "@/lib/workspace";

interface Message {
  id: string;
  role: "user" | "assistant";
  content: string;
}

const GREETING: Message = {
  id: "greeting",
  role: "assistant",
  content:
    "Hi — I'm your PulseLoop assistant. I adapt to the modules you've enabled. Ask me about your health, planning, habits, tasks, notes, or anything you're working through.",
};

// Suggestions adapt to which modules are enabled (the adaptive-chat intent).
const MODULE_SUGGESTIONS: Partial<Record<ModuleId, string>> = {
  day_plan: "Help me plan my day",
  tasks: "What should I focus on next?",
  protocol: "Review my protocol timing",
  sleep: "How was my sleep this week?",
  workouts: "Suggest today's workout",
  nutrition: "How are my macros looking?",
  journal: "Reflect on my recent journal entries",
};

function uid() {
  return Math.random().toString(36).slice(2);
}

export function CoachScreen() {
  const { modules } = useWorkspace();
  const [messages, setMessages] = useState<Message[]>([GREETING]);
  const [input, setInput] = useState("");
  const [sending, setSending] = useState(false);
  const [balance, setBalance] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);

  const suggestions = useMemo(() => {
    const fromModules = (Object.keys(MODULE_SUGGESTIONS) as ModuleId[])
      .filter((m) => modules[m])
      .map((m) => MODULE_SUGGESTIONS[m]!)
      .slice(0, 3);
    return ["What can you help me with?", ...fromModules];
  }, [modules]);

  useEffect(() => {
    scrollRef.current?.scrollTo({
      top: scrollRef.current.scrollHeight,
      behavior: "smooth",
    });
  }, [messages, sending]);

  async function send(override?: string) {
    const text = (override ?? input).trim();
    if (!text || sending) return;
    setError(null);

    const userMsg: Message = { id: uid(), role: "user", content: text };
    const history = messages
      .filter((m) => m.id !== "greeting")
      .map((m) => ({ role: m.role, content: m.content }));

    setMessages((prev) => [...prev, userMsg]);
    setInput("");
    setSending(true);

    try {
      const res = await fetch("/api/v1/coach/web", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: text, history }),
      });

      if (res.status === 402) {
        setError("You're out of credits. Buy more in the PulseLoop iPhone app.");
        const data = await res.json().catch(() => ({}));
        if (typeof data.balance === "number") setBalance(data.balance);
        return;
      }
      if (!res.ok) throw new Error(`HTTP ${res.status}`);

      const data = (await res.json()) as { reply: string; balance: number };
      setMessages((prev) => [
        ...prev,
        { id: uid(), role: "assistant", content: data.reply },
      ]);
      if (typeof data.balance === "number") setBalance(data.balance);
    } catch {
      setError("Something went wrong. Try again.");
    } finally {
      setSending(false);
    }
  }

  function onKeyDown(e: React.KeyboardEvent<HTMLTextAreaElement>) {
    if (e.key === "Enter" && !e.shiftKey) {
      e.preventDefault();
      void send();
    }
  }

  return (
    <div className="flex min-h-[calc(100vh-180px)] flex-col">
      <div className="flex items-center gap-3.5">
        <div className="bg-accent text-on-accent flex h-12 w-12 shrink-0 items-center justify-center rounded-[14px]">
          <Icons.sparkLg />
        </div>
        <div>
          <h1 className="text-text-primary m-0 font-serif text-[34px] leading-none font-normal tracking-tight">
            Ask AI
          </h1>
          <p className="text-text-muted mt-1.5 text-[15px]">
            Your adaptive life-OS assistant
          </p>
        </div>
      </div>

      <div
        ref={scrollRef}
        className="mt-6 flex-1 space-y-3 overflow-y-auto"
        aria-live="polite"
      >
        {messages.map((m) => (
          <Bubble key={m.id} role={m.role}>
            {m.content}
          </Bubble>
        ))}
        {messages.length === 1 && !sending && (
          <div className="flex flex-wrap gap-2 pt-1">
            {suggestions.map((s) => (
              <button
                key={s}
                type="button"
                onClick={() => void send(s)}
                className="border-border-hairline bg-fill-subtle text-text-secondary rounded-full border px-3.5 py-2 text-[13.5px] font-medium hover:opacity-70"
              >
                {s}
              </button>
            ))}
          </div>
        )}
        {sending && (
          <div className="bg-fill-subtle text-text-muted w-fit rounded-[18px] px-4 py-3 text-[15px]">
            <span className="inline-flex gap-1">
              <Dot /> <Dot /> <Dot />
            </span>
          </div>
        )}
      </div>

      <div className="bg-canvas sticky bottom-0 pt-4">
        {error && <p className="text-alert mb-2 text-sm">{error}</p>}
        <div className="bg-fill-subtle border-border-hairline flex items-end gap-2 rounded-[18px] border px-3 py-2">
          <span className="text-text-muted pb-2 pl-1">
            <Icons.spark />
          </span>
          <textarea
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={onKeyDown}
            rows={1}
            placeholder="Message your assistant…"
            className="text-text-primary placeholder:text-text-muted max-h-32 flex-1 resize-none bg-transparent py-1.5 text-[15px] outline-none"
          />
          <button
            type="button"
            onClick={() => void send()}
            disabled={sending || !input.trim()}
            aria-label="Send"
            className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-black text-white transition disabled:opacity-40 dark:bg-white dark:text-black"
          >
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none">
              <path d="M12 20V5M5 12l7-7 7 7" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </button>
        </div>
        {balance !== null && (
          <p className="text-text-muted mt-2 text-center text-xs">
            {balance} credits remaining
          </p>
        )}
      </div>
    </div>
  );
}

function Bubble({
  role,
  children,
}: {
  role: "user" | "assistant";
  children: React.ReactNode;
}) {
  const sent = role === "user";
  return (
    <div className={sent ? "flex justify-end" : "flex justify-start"}>
      <div
        className={
          sent
            ? "max-w-[80%] rounded-[18px] bg-black px-4 py-2.5 text-[15px] whitespace-pre-wrap text-white dark:bg-white dark:text-black"
            : "bg-fill-subtle text-text-primary max-w-[80%] rounded-[18px] px-4 py-2.5 text-[15px] whitespace-pre-wrap"
        }
      >
        {children}
      </div>
    </div>
  );
}

function Dot() {
  return (
    <span className="bg-text-muted inline-block h-1.5 w-1.5 animate-pulse rounded-full" />
  );
}
