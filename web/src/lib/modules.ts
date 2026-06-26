// Module catalog metadata shared by the Modules screen (list + detail) and the
// command palette. The *enabled* state lives in user_settings (see workspace.ts);
// this file is the static descriptor (name, copy, version, permissions, changelog)
// ported from the prototype CATALOG and the iOS SubAppRegistry.

import type { ModuleId } from "./workspace";
import type { IconName } from "@/components/workspace/icons";

export interface ModuleChangelog {
  version: string;
  date: string;
  notes: string;
}

export interface ModuleDescriptor {
  id: ModuleId;
  name: string;
  icon: IconName;
  summary: string;
  description: string;
  version: string;
  author: string;
  permissions: string[];
  changelog: ModuleChangelog[];
}

export const MODULE_CATALOG: ModuleDescriptor[] = [
  {
    id: "tasks",
    name: "Tasks",
    icon: "check",
    summary: "Kanban board with drag-between-columns and inline capture.",
    description:
      "A calm task board. Capture from anywhere, organize across To do / Doing / Done, and let the agent file new tasks for you.",
    version: "1.4.0",
    author: "PulseLoop",
    permissions: ["Notifications — reminders for due tasks"],
    changelog: [
      { version: "1.4.0", date: "Jun 2026", notes: "Inline add per column and keyboard reorder." },
      { version: "1.3.0", date: "Apr 2026", notes: "Drag between columns with live counts." },
    ],
  },
  {
    id: "notes",
    name: "Notes",
    icon: "doc",
    summary: "Live editor with a running AI summary and task extraction.",
    description:
      "Long-form notes with word/character counts and commit-on-blur. PulseLoop keeps a running summary and can extract tasks.",
    version: "1.2.0",
    author: "PulseLoop",
    permissions: [],
    changelog: [
      { version: "1.2.0", date: "May 2026", notes: "AI summary and link-note toolbar." },
      { version: "1.1.0", date: "Feb 2026", notes: "Word & character counts." },
    ],
  },
  {
    id: "protocol",
    name: "Protocol",
    icon: "pill",
    summary: "Supplements, medications & peptides with full dosing.",
    description:
      "Track everything you take with dose and timing. Surfaces in your Home feed and Today's plan.",
    version: "2.0.0",
    author: "PulseLoop",
    permissions: ["Notifications — dosing reminders"],
    changelog: [
      { version: "2.0.0", date: "Jun 2026", notes: "Peptide and medication types with timing." },
      { version: "1.0.0", date: "Jan 2026", notes: "Initial supplement tracking." },
    ],
  },
  {
    id: "ai_capture",
    name: "AI Capture",
    icon: "inbox",
    summary: "Triage AI-suggested items in bulk — accept or dismiss fast.",
    description:
      "Everything the agent notices lands here. Multi-select and file or dismiss in one pass.",
    version: "1.1.0",
    author: "PulseLoop",
    permissions: ["Microphone — voice capture", "Camera — meal & product scanning"],
    changelog: [
      { version: "1.1.0", date: "May 2026", notes: "Bulk accept & dismiss." },
      { version: "1.0.0", date: "Mar 2026", notes: "AI inbox introduced." },
    ],
  },
  {
    id: "nutrition",
    name: "Nutrition",
    icon: "fork",
    summary: "Log meals with macros and a daily calorie roll-up.",
    description:
      "Quick meal logging with protein/carb/fat tracking and a running kcal total for the day.",
    version: "1.3.0",
    author: "PulseLoop",
    permissions: ["Camera — meal scanning"],
    changelog: [
      { version: "1.3.0", date: "Jun 2026", notes: "Macro breakdown bars." },
      { version: "1.0.0", date: "Feb 2026", notes: "Meal log." },
    ],
  },
  {
    id: "sleep",
    name: "Sleep",
    icon: "moon",
    summary: "Sleep score, hypnogram & stages synced from your phone.",
    description:
      "Last night's sleep score with a stage-by-stage hypnogram synced from Apple Health.",
    version: "1.2.0",
    author: "PulseLoop",
    permissions: ["Apple Health — read sleep"],
    changelog: [
      { version: "1.2.0", date: "May 2026", notes: "Hypnogram view." },
      { version: "1.0.0", date: "Jan 2026", notes: "Sleep score." },
    ],
  },
  {
    id: "workouts",
    name: "Fitness",
    icon: "dumbbell",
    summary: "Activity rings, templates & a 30-day movement view.",
    description:
      "Workout templates and a 30-day activity summary pulled from Apple Health.",
    version: "1.1.0",
    author: "PulseLoop",
    permissions: ["Apple Health — read workouts"],
    changelog: [
      { version: "1.1.0", date: "Apr 2026", notes: "Workout templates." },
      { version: "1.0.0", date: "Jan 2026", notes: "Activity view." },
    ],
  },
  {
    id: "mood",
    name: "Mood",
    icon: "smile",
    summary: "A quick daily energy & mood check-in.",
    description:
      "One-tap energy and mood check-ins that feed your weekly AI insights.",
    version: "1.0.0",
    author: "PulseLoop",
    permissions: [],
    changelog: [{ version: "1.0.0", date: "Mar 2026", notes: "Daily check-in." }],
  },
  {
    id: "day_plan",
    name: "Today's plan",
    icon: "calCheck",
    summary: "An AI-drafted daily schedule from tasks, protocol & habits.",
    description:
      "PulseLoop drafts your day from open tasks, protocol timing and habits, and logs every agent action.",
    version: "1.2.0",
    author: "PulseLoop",
    permissions: [],
    changelog: [
      { version: "1.2.0", date: "Jun 2026", notes: "Agent action log." },
      { version: "1.0.0", date: "Feb 2026", notes: "Daily schedule." },
    ],
  },
  {
    id: "quit_program",
    name: "Quit program",
    icon: "flame",
    summary: "Streak-based programs to quit a habit for good.",
    description:
      "Track clean streaks, money saved and your best run for any habit you're quitting.",
    version: "1.0.0",
    author: "PulseLoop",
    permissions: ["Notifications — streak nudges"],
    changelog: [{ version: "1.0.0", date: "Apr 2026", notes: "Quit programs." }],
  },
  {
    id: "journal",
    name: "Journal",
    icon: "book",
    summary: "Mood-tagged journal entries with a quick composer.",
    description:
      "Capture how you're feeling with an emoji tag and a free-text entry that feeds your insights.",
    version: "1.1.0",
    author: "PulseLoop",
    permissions: [],
    changelog: [
      { version: "1.1.0", date: "May 2026", notes: "Mood tags." },
      { version: "1.0.0", date: "Feb 2026", notes: "Journal." },
    ],
  },
  {
    id: "accountability",
    name: "Accountability",
    icon: "flame",
    summary: "Streaks, quit programs & friends keeping you honest.",
    description:
      "See your quit-program streaks alongside friends so you stay accountable.",
    version: "1.0.0",
    author: "PulseLoop",
    permissions: [],
    changelog: [{ version: "1.0.0", date: "Apr 2026", notes: "Friends & streaks." }],
  },
  {
    id: "travel",
    name: "Travel",
    icon: "plane",
    summary: "Plan trips with an AI-built itinerary, budget & bookings.",
    description:
      "Design trips end-to-end: destinations, flights, lodging, activities and a day-by-day itinerary with a live budget roll-up. The agent can research and assemble plans, and everything syncs here read-only.",
    version: "1.0.0",
    author: "PulseLoop",
    permissions: [],
    changelog: [{ version: "1.0.0", date: "Jun 2026", notes: "Trips, itineraries & budget sync." }],
  },
];

export const MODULE_BY_ID: Record<ModuleId, ModuleDescriptor> =
  Object.fromEntries(MODULE_CATALOG.map((m) => [m.id, m])) as Record<
    ModuleId,
    ModuleDescriptor
  >;
