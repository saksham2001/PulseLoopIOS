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
import {
  DEFAULT_WORKSPACE,
  type HomeSection,
  type ModuleId,
  type PermissionSetting,
  type Theme,
  type WorkspaceSettings,
} from "@/lib/workspace";

interface WorkspaceContextValue extends WorkspaceSettings {
  ready: boolean;
  isEnabled: (id: ModuleId) => boolean;
  setModule: (id: ModuleId, on: boolean) => void;
  toggleModule: (id: ModuleId) => void;
  setHomeLayout: (layout: HomeSection[]) => void;
  setTheme: (theme: Theme) => void;
  toggleTheme: () => void;
  setPermission: (id: string, on: boolean) => void;
}

const WorkspaceContext = createContext<WorkspaceContextValue | null>(null);

/**
 * Single source of truth for workspace prefs (modules, Home layout, theme,
 * permissions). Hydrates from `/api/settings`, applies the theme to the document,
 * and debounce-persists every mutation back to the server (so state survives
 * reload via the real backend, not localStorage).
 */
export function WorkspaceProvider({
  initial,
  children,
}: {
  initial?: WorkspaceSettings;
  children: ReactNode;
}) {
  const [settings, setSettings] = useState<WorkspaceSettings>(
    initial ?? DEFAULT_WORKSPACE,
  );
  const [ready, setReady] = useState(Boolean(initial));
  const saveTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const skipNextSave = useRef(true);

  // Hydrate from server when no SSR snapshot was provided.
  useEffect(() => {
    if (initial) return;
    let active = true;
    (async () => {
      try {
        const res = await fetch("/api/settings");
        if (res.ok && active) {
          const data: WorkspaceSettings = await res.json();
          skipNextSave.current = true;
          setSettings(data);
        }
      } catch {
        // fall back to defaults already in state
      } finally {
        if (active) setReady(true);
      }
    })();
    return () => {
      active = false;
    };
  }, [initial]);

  // Apply theme to <html> so tokens flip app-wide.
  useEffect(() => {
    const el = document.documentElement;
    el.setAttribute("data-theme", settings.theme);
    el.classList.toggle("dark", settings.theme === "dark");
  }, [settings.theme]);

  // Debounced persist of the whole settings blob.
  useEffect(() => {
    if (skipNextSave.current) {
      skipNextSave.current = false;
      return;
    }
    if (saveTimer.current) clearTimeout(saveTimer.current);
    saveTimer.current = setTimeout(() => {
      fetch("/api/settings", {
        method: "PATCH",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(settings),
      }).catch(() => {});
    }, 350);
    return () => {
      if (saveTimer.current) clearTimeout(saveTimer.current);
    };
  }, [settings]);

  const isEnabled = useCallback(
    (id: ModuleId) => settings.modules[id] ?? false,
    [settings.modules],
  );

  const setModule = useCallback((id: ModuleId, on: boolean) => {
    setSettings((s) => ({ ...s, modules: { ...s.modules, [id]: on } }));
  }, []);

  const toggleModule = useCallback((id: ModuleId) => {
    setSettings((s) => ({ ...s, modules: { ...s.modules, [id]: !s.modules[id] } }));
  }, []);

  const setHomeLayout = useCallback((layout: HomeSection[]) => {
    setSettings((s) => ({ ...s, homeLayout: layout }));
  }, []);

  const setTheme = useCallback((theme: Theme) => {
    setSettings((s) => ({ ...s, theme }));
  }, []);

  const toggleTheme = useCallback(() => {
    setSettings((s) => ({ ...s, theme: s.theme === "dark" ? "light" : "dark" }));
  }, []);

  const setPermission = useCallback((id: string, on: boolean) => {
    setSettings((s) => ({
      ...s,
      permissions: s.permissions.map((p) => (p.id === id ? { ...p, on } : p)),
    }));
  }, []);

  const value = useMemo<WorkspaceContextValue>(
    () => ({
      ...settings,
      ready,
      isEnabled,
      setModule,
      toggleModule,
      setHomeLayout,
      setTheme,
      toggleTheme,
      setPermission,
    }),
    [
      settings,
      ready,
      isEnabled,
      setModule,
      toggleModule,
      setHomeLayout,
      setTheme,
      toggleTheme,
      setPermission,
    ],
  );

  return (
    <WorkspaceContext.Provider value={value}>
      {children}
    </WorkspaceContext.Provider>
  );
}

export function useWorkspace(): WorkspaceContextValue {
  const ctx = useContext(WorkspaceContext);
  if (!ctx) {
    throw new Error("useWorkspace must be used within a WorkspaceProvider");
  }
  return ctx;
}

export type { PermissionSetting };
