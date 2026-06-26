"use client";

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react";
import { useRouter } from "next/navigation";
import { Icons, type IconName } from "./icons";
import { useWorkspace } from "./workspace-context";

interface PaletteContextValue {
  open: () => void;
  close: () => void;
  isOpen: boolean;
}

const PaletteContext = createContext<PaletteContextValue | null>(null);

interface Command {
  label: string;
  icon: IconName;
  hint?: string;
  run: () => void;
}

export function CommandPaletteProvider({ children }: { children: ReactNode }) {
  const router = useRouter();
  const { theme, toggleTheme } = useWorkspace();
  const [isOpen, setIsOpen] = useState(false);
  const [query, setQuery] = useState("");
  const inputRef = useRef<HTMLInputElement>(null);

  const open = useCallback(() => {
    setQuery("");
    setIsOpen(true);
  }, []);
  const close = useCallback(() => setIsOpen(false), []);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setIsOpen((v) => !v);
        setQuery("");
      }
      if (e.key === "Escape") setIsOpen(false);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  useEffect(() => {
    if (isOpen) {
      const t = setTimeout(() => inputRef.current?.focus(), 30);
      return () => clearTimeout(t);
    }
  }, [isOpen]);

  const commands = useMemo<Command[]>(() => {
    const go = (href: string) => () => {
      setIsOpen(false);
      router.push(href);
    };
    return [
      { label: "New task", icon: "check", hint: "Tasks", run: go("/tasks") },
      { label: "New note", icon: "doc", hint: "Notes", run: go("/notes") },
      { label: "Add protocol item", icon: "pill", hint: "Protocol", run: go("/protocol") },
      { label: "Log a meal", icon: "fork", hint: "Nutrition", run: go("/nutrition") },
      { label: "Check in mood", icon: "smile", hint: "Mood", run: go("/mood") },
      { label: "Ask AI", icon: "spark", hint: "Coach", run: go("/coach") },
      { label: "Today's plan", icon: "calCheck", run: go("/today") },
      { label: "Go to AI Capture", icon: "inbox", run: go("/capture") },
      { label: "Go to Tracker", icon: "chart", run: go("/tracker") },
      { label: "Go to Sleep", icon: "moon", run: go("/sleep") },
      { label: "Go to Fitness", icon: "dumbbell", run: go("/fitness") },
      { label: "Go to Modules", icon: "grid", run: go("/modules") },
      {
        label: theme === "dark" ? "Switch to light mode" : "Switch to dark mode",
        icon: theme === "dark" ? "sun" : "moon",
        run: () => {
          toggleTheme();
          setIsOpen(false);
        },
      },
    ];
  }, [router, theme, toggleTheme]);

  const q = query.trim().toLowerCase();
  const filtered = commands.filter((c) => !q || c.label.toLowerCase().includes(q));
  const createTask = q && filtered.length === 0 ? query.trim() : "";

  const runCreateTask = useCallback(async () => {
    const title = query.trim();
    if (!title) return;
    setIsOpen(false);
    try {
      await fetch("/api/records", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          type: "task",
          payload: { title, status: "todo", label: "Today" },
        }),
      });
    } catch {
      // navigation still proceeds
    }
    router.push("/tasks");
  }, [query, router]);

  const value = useMemo(() => ({ open, close, isOpen }), [open, close, isOpen]);

  return (
    <PaletteContext.Provider value={value}>
      {children}
      {isOpen && (
        <div
          onClick={close}
          className="fixed inset-0 z-50 flex justify-center bg-black/30 pt-[14vh]"
        >
          <div
            onClick={(e) => e.stopPropagation()}
            className="bg-background border-border-strong w-[560px] max-w-[92vw] overflow-hidden rounded-[16px] border shadow-2xl"
          >
            <div className="border-border-hairline flex items-center gap-3 border-b px-[18px] py-4">
              <span className="text-text-muted flex w-[18px]">
                <Icons.search />
              </span>
              <input
                ref={inputRef}
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter") {
                    if (createTask) void runCreateTask();
                    else filtered[0]?.run();
                  }
                }}
                placeholder="Type a command, or write a task and press Enter…"
                className="flex-1 bg-transparent text-[16px] outline-none"
              />
              <span className="border-border-strong text-text-muted rounded-[6px] border px-1.5 py-0.5 text-[11px] font-semibold">
                esc
              </span>
            </div>
            <div className="max-h-[360px] overflow-y-auto p-2">
              {filtered.map((c) => {
                const Icon = Icons[c.icon];
                return (
                  <button
                    type="button"
                    key={c.label}
                    onClick={c.run}
                    className="hover:bg-fill-subtle flex w-full items-center gap-3 rounded-[10px] p-3 text-left"
                  >
                    <span className="text-text-secondary flex w-5 justify-center">
                      <Icon />
                    </span>
                    <span className="text-[15px] font-medium">{c.label}</span>
                    {c.hint && (
                      <span className="text-text-muted ml-auto text-[12px]">
                        {c.hint}
                      </span>
                    )}
                  </button>
                );
              })}
              {createTask && (
                <button
                  type="button"
                  onClick={runCreateTask}
                  className="bg-fill-subtle flex w-full items-center gap-3 rounded-[10px] p-3 text-left"
                >
                  <span className="text-text-secondary flex w-5 justify-center">
                    ＋
                  </span>
                  <span className="text-[15px] font-medium">
                    Create task “{createTask}”
                  </span>
                  <span className="text-text-muted ml-auto text-[12px]">
                    Enter ↵
                  </span>
                </button>
              )}
            </div>
          </div>
        </div>
      )}
    </PaletteContext.Provider>
  );
}

export function usePalette(): PaletteContextValue {
  const ctx = useContext(PaletteContext);
  if (!ctx) throw new Error("usePalette must be used within CommandPaletteProvider");
  return ctx;
}
