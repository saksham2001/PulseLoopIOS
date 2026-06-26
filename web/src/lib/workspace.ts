// Workspace defaults + types shared by the web app shell, Home feed, and Modules
// screen. Mirrors the prototype's module catalog + default Home layout, but the
// live values are persisted per-user in `user_settings` (see /api/settings).

export type Theme = "light" | "dark";

/** Module ids that gate nav items / Home sections / routes. Mirrors the iOS
 * SubApp ids and the prototype's CATALOG. */
export const MODULE_IDS = [
  "tasks",
  "notes",
  "protocol",
  "ai_capture",
  "nutrition",
  "sleep",
  "workouts",
  "mood",
  "day_plan",
  "quit_program",
  "journal",
  "accountability",
  "travel",
] as const;

export type ModuleId = (typeof MODULE_IDS)[number];

/** Default enabled state per module (prototype CATALOG `installed`). */
export const DEFAULT_MODULES: Record<ModuleId, boolean> = {
  tasks: true,
  notes: true,
  protocol: true,
  ai_capture: true,
  nutrition: true,
  sleep: true,
  workouts: true,
  mood: true,
  day_plan: true,
  quit_program: false,
  journal: true,
  accountability: true,
  travel: true,
};

/** Home feed section ids and their default span (2 = full width, 1 = half). */
export interface HomeSection {
  id: string;
  span: 1 | 2;
}

export const HOME_SECTION_META: Record<
  string,
  { title: string; meta: string; defaultSpan: 1 | 2; module?: ModuleId }
> = {
  upnext: { title: "Up Next", meta: "Open tracker →", defaultSpan: 2 },
  tasks: { title: "Today · Tasks", meta: "", defaultSpan: 1, module: "tasks" },
  rightnow: { title: "Right Now", meta: "", defaultSpan: 1 },
  aidigest: { title: "AI Digest", meta: "", defaultSpan: 1 },
  protocol: { title: "Protocol", meta: "", defaultSpan: 1, module: "protocol" },
  vitals: { title: "Vitals", meta: "Today", defaultSpan: 2 },
};

export const DEFAULT_HOME_LAYOUT: HomeSection[] = [
  { id: "upnext", span: 2 },
  { id: "tasks", span: 1 },
  { id: "rightnow", span: 1 },
  { id: "aidigest", span: 1 },
  { id: "vitals", span: 2 },
];

export interface PermissionSetting {
  id: string;
  label: string;
  detail: string;
  on: boolean;
}

export const DEFAULT_PERMISSIONS: PermissionSetting[] = [
  {
    id: "apple_health",
    label: "Apple Health",
    detail: "Read heart rate, sleep, steps & workouts",
    on: true,
  },
  {
    id: "microphone",
    label: "Microphone",
    detail: "Voice capture & dictation",
    on: true,
  },
  {
    id: "camera",
    label: "Camera",
    detail: "Meal & product scanning",
    on: true,
  },
  {
    id: "notifications",
    label: "Notifications",
    detail: "Reminders for protocol & tasks",
    on: true,
  },
  {
    id: "analytics",
    label: "Share usage analytics",
    detail: "Anonymous, helps improve PulseLoop",
    on: false,
  },
];

export interface WorkspaceSettings {
  modules: Record<ModuleId, boolean>;
  homeLayout: HomeSection[];
  theme: Theme;
  permissions: PermissionSetting[];
}

export const DEFAULT_WORKSPACE: WorkspaceSettings = {
  modules: DEFAULT_MODULES,
  homeLayout: DEFAULT_HOME_LAYOUT,
  theme: "light",
  permissions: DEFAULT_PERMISSIONS,
};

/** Merge a (possibly partial / stale) persisted blob onto the defaults so newly
 * added modules/sections always resolve. */
export function normalizeWorkspace(raw: {
  modules?: unknown;
  homeLayout?: unknown;
  theme?: unknown;
  permissions?: unknown;
} | null): WorkspaceSettings {
  const modules = { ...DEFAULT_MODULES };
  if (raw?.modules && typeof raw.modules === "object") {
    for (const id of MODULE_IDS) {
      const v = (raw.modules as Record<string, unknown>)[id];
      if (typeof v === "boolean") modules[id] = v;
    }
  }

  let homeLayout = DEFAULT_HOME_LAYOUT;
  if (Array.isArray(raw?.homeLayout)) {
    const cleaned = (raw.homeLayout as unknown[])
      .map((s) => {
        if (!s || typeof s !== "object") return null;
        const id = (s as { id?: unknown }).id;
        const span = (s as { span?: unknown }).span;
        if (typeof id !== "string" || !HOME_SECTION_META[id]) return null;
        return { id, span: span === 1 ? 1 : 2 } as HomeSection;
      })
      .filter((s): s is HomeSection => s !== null);
    if (cleaned.length > 0) homeLayout = cleaned;
  }

  const theme: Theme = raw?.theme === "dark" ? "dark" : "light";

  let permissions = DEFAULT_PERMISSIONS;
  if (Array.isArray(raw?.permissions)) {
    const byId = new Map<string, boolean>();
    for (const p of raw.permissions as unknown[]) {
      if (p && typeof p === "object") {
        const id = (p as { id?: unknown }).id;
        const on = (p as { on?: unknown }).on;
        if (typeof id === "string" && typeof on === "boolean") byId.set(id, on);
      }
    }
    permissions = DEFAULT_PERMISSIONS.map((p) =>
      byId.has(p.id) ? { ...p, on: byId.get(p.id)! } : p,
    );
  }

  return { modules, homeLayout, theme, permissions };
}
