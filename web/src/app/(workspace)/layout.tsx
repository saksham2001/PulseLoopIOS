import type { ReactNode } from "react";
import { WorkspaceShell } from "@/components/workspace/workspace-shell";
import { loadWorkspaceSettings } from "@/lib/workspace-server";

/**
 * Layout for all workspace screens. Loads the user's settings server-side and
 * hands them to the client shell as the initial snapshot.
 */
export default async function WorkspaceLayout({
  children,
}: {
  children: ReactNode;
}) {
  const initial = await loadWorkspaceSettings();
  return <WorkspaceShell initial={initial}>{children}</WorkspaceShell>;
}
