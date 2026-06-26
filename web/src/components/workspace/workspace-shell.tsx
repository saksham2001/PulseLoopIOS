"use client";

import type { ReactNode } from "react";
import { Sidebar } from "./sidebar";
import { AskAiFab } from "./ask-ai-fab";
import { CommandPaletteProvider } from "./command-palette";
import { WorkspaceProvider } from "./workspace-context";
import type { WorkspaceSettings } from "@/lib/workspace";

/**
 * The shared workspace shell: sidebar + scrolling main + ⌘K palette + Ask-AI FAB,
 * matching the prototype's two-pane layout. All workspace routes render inside
 * `children`. `initial` is the SSR snapshot of the user's settings so the first
 * paint already has the right theme + module visibility (no flash).
 */
export function WorkspaceShell({
  initial,
  children,
}: {
  initial: WorkspaceSettings;
  children: ReactNode;
}) {
  return (
    <WorkspaceProvider initial={initial}>
      <CommandPaletteProvider>
        <div className="bg-canvas text-text-primary flex h-screen w-full overflow-hidden">
          <Sidebar />
          <main className="relative flex-1 overflow-y-auto">
            <div className="mx-auto max-w-[980px] px-10 pt-9 pb-[100px]">
              {children}
            </div>
          </main>
          <AskAiFab />
        </div>
      </CommandPaletteProvider>
    </WorkspaceProvider>
  );
}
