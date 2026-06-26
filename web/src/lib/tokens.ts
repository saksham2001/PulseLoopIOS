/**
 * PulseLoop design tokens (web) — kept in 1:1 sync with the iOS source of truth:
 *   - Colors:  PulseLoop/Assets.xcassets/*.colorset/Contents.json
 *   - Type:    PulseLoop/App/AppTheme.swift (PulseFont)
 *   - Layout:  PulseLoop/App/AppTheme.swift (PulseRadius / PulseLayout)
 *
 * Prefer the Tailwind utility classes generated from globals.css `@theme`
 * (e.g. `bg-background`, `text-text-primary`, `border-border-hairline`).
 * Use these constants only when a raw value is needed (canvas drawing, inline
 * styles, charts, etc.).
 */

export const pulseColors = {
  light: {
    background: "#ffffff",
    canvas: "#ececee",
    fillSubtle: "#f4f4f3",
    fillMuted: "#fafafa",
    borderHairline: "#ececec",
    borderStrong: "#e4e4e2",
    textPrimary: "#1b1b1a",
    textSecondary: "#6e6e6c",
    textMuted: "#9a9a98",
    textFaint: "#b4b4b2",
    accent: "#161616",
  },
  dark: {
    background: "#0a0a0c",
    canvas: "#1c1c1e",
    fillSubtle: "#2c2c2e",
    fillMuted: "#252528",
    borderHairline: "#38383a",
    borderStrong: "#48484a",
    textPrimary: "#f5f7fa",
    textSecondary: "#aab3c2",
    textMuted: "#6f7a8c",
    textFaint: "#8e8e93",
    accent: "#ffffff",
  },
} as const;

/** Semantic + health-metric colors are appearance-independent on iOS. */
export const pulseSemantic = {
  success: "#2f7d5b",
  alert: "#b4453a",
  warning: "#b8860b",
  heartRate: "#b4453a",
  steps: "#2f7d5b",
  spo2: "#4a7fb5",
  sleep: "#6b5fa0",
  sleepScore: "#8b7cff",
  calories: "#c47230",
  distance: "#4a7fb5",
  battery: "#2f7d5b",
  readiness: "#5b7d2f",
} as const;

/** Corner radii (px) — mirrors iOS PulseRadius. */
export const pulseRadius = {
  card: 14,
  button: 12,
  chip: 6,
  icon: 8,
} as const;

/** Spacing / sizing (px) — mirrors iOS PulseLayout + the design-system rule. */
export const pulseLayout = {
  pagePadding: 20,
  cardPadding: 16,
  buttonHeight: 44,
  buttonHeightLarge: 52,
  interCardSpacing: 14,
} as const;

/** Type scale (px) — mirrors the iOS PulseFont usage table. */
export const pulseType = {
  title: 28,
  cardTitle: 22,
  body: 15,
  bodySmall: 14,
  button: 15,
  chip: 12,
  sectionLabel: 11,
} as const;

export type PulseColorScheme = keyof typeof pulseColors;
