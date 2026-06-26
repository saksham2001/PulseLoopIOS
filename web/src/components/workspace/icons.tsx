import type { ReactNode } from "react";

// Line/solid icon set ported 1:1 from the prototype's ICON map so the web shell
// matches the design's iconography exactly. Each icon is a 24×24 SVG; stroke
// icons inherit `currentColor`, fill icons use `currentColor`.

function svg(children: ReactNode, opts?: { fill?: boolean; size?: number }) {
  const size = opts?.size ?? 19;
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill={opts?.fill ? "currentColor" : "none"}
      stroke={opts?.fill ? undefined : "currentColor"}
      strokeWidth={opts?.fill ? undefined : 1.8}
      aria-hidden="true"
    >
      {children}
    </svg>
  );
}

export const Icons = {
  home: () => svg(<path d="M3 11l9-8 9 8M5 10v9h5v-6h4v6h5v-9" />),
  inbox: () => svg(<path d="M3 13h4l2 3h6l2-3h4M3 13l3-8h12l3 8v6H3v-6z" />),
  doc: () =>
    svg(
      <>
        <path d="M6 2h8l4 4v16H6V2z" />
        <path d="M14 2v4h4" />
      </>,
    ),
  check: () =>
    svg(
      <>
        <circle cx="8" cy="7" r="3" />
        <path d="M14 7h6M8 17h0M14 17h6" />
        <circle cx="8" cy="17" r="3" />
      </>,
    ),
  pill: () =>
    svg(
      <>
        <path d="M4.5 12.5l8-8a4 4 0 0 1 6 6l-8 8a4 4 0 0 1-6-6z" />
        <path d="M8.5 8.5l6 6" />
      </>,
    ),
  spark: () =>
    svg(<path d="M12 2l1.6 4.4L18 8l-4.4 1.6L12 14l-1.6-4.4L6 8l4.4-1.6L12 2z" />, {
      fill: true,
    }),
  sparkLg: () =>
    svg(<path d="M12 2l1.6 4.4L18 8l-4.4 1.6L12 14l-1.6-4.4L6 8l4.4-1.6L12 2z" />, {
      fill: true,
      size: 22,
    }),
  chart: () =>
    svg(
      <>
        <path d="M3 17l5-6 4 4 6-8" />
        <path d="M18 7h3v3" />
      </>,
    ),
  trend: () => svg(<path d="M3 17l6-6 4 4 8-9" />),
  user: () =>
    svg(
      <>
        <circle cx="12" cy="9" r="3.5" />
        <path d="M5 20a7 7 0 0 1 14 0" />
      </>,
    ),
  grid: () =>
    svg(
      <>
        <rect x="3" y="3" width="7" height="7" rx="1.5" />
        <rect x="14" y="3" width="7" height="7" rx="1.5" />
        <rect x="3" y="14" width="7" height="7" rx="1.5" />
        <rect x="14" y="14" width="7" height="7" rx="1.5" />
      </>,
      { fill: true },
    ),
  syringe: () =>
    svg(
      <>
        <path d="M18 2l4 4M16 4l4 4-8 8-4 1 1-4 7-9z" />
        <path d="M14 8l-9 9-3 5 5-3 9-9" />
      </>,
    ),
  sun: () =>
    svg(
      <>
        <circle cx="12" cy="12" r="4" />
        <path d="M12 2v2M12 20v2M2 12h2M20 12h2M5 5l1.5 1.5M17.5 17.5L19 19M19 5l-1.5 1.5M6.5 17.5L5 19" />
      </>,
    ),
  moon: () => svg(<path d="M20 14a8 8 0 1 1-9-11 6 6 0 0 0 9 11z" />),
  cal: () =>
    svg(
      <>
        <rect x="3" y="5" width="18" height="16" rx="2" />
        <path d="M3 9h18M8 3v4M16 3v4" />
      </>,
    ),
  calCheck: () =>
    svg(
      <>
        <rect x="3" y="4" width="18" height="17" rx="2" />
        <path d="M3 9h18M8 14l3 3 5-5" />
      </>,
    ),
  search: () =>
    svg(
      <>
        <circle cx="11" cy="11" r="7" />
        <path d="M21 21l-4-4" />
      </>,
      { size: 17 },
    ),
  book: () =>
    svg(
      <>
        <path d="M5 4h12a2 2 0 0 1 2 2v14H7a2 2 0 0 1-2-2V4z" />
        <path d="M5 18a2 2 0 0 1 2-2h12" />
      </>,
    ),
  dumbbell: () => svg(<path d="M4 9v6M7 7v10M17 7v10M20 9v6M7 12h10" />),
  flame: () =>
    svg(
      <path d="M12 3c1 3 4 4 4 8a4 4 0 0 1-8 0c0-2 1-3 1-3 0 2 2 2 2 0 0-2 0-3-1-5z" />,
    ),
  fork: () => svg(<path d="M6 3v7a2 2 0 0 0 4 0V3M8 12v9M18 3c-2 1-3 3-3 6h3v12" />),
  smile: () =>
    svg(
      <>
        <circle cx="12" cy="12" r="9" />
        <path d="M8 14s1.5 2 4 2 4-2 4-2M9 9h.01M15 9h.01" />
      </>,
    ),
  gear: () =>
    svg(
      <>
        <circle cx="12" cy="12" r="3" />
        <path d="M19 12a7 7 0 0 0-.1-1l2-1.5-2-3.4-2.3 1a7 7 0 0 0-1.7-1l-.3-2.6h-4l-.3 2.6a7 7 0 0 0-1.7 1l-2.3-1-2 3.4 2 1.5a7 7 0 0 0 0 2l-2 1.5 2 3.4 2.3-1a7 7 0 0 0 1.7 1l.3 2.6h4l.3-2.6a7 7 0 0 0 1.7-1l2.3 1 2-3.4-2-1.5c.1-.3.1-.7.1-1z" />
      </>,
    ),
  link: () =>
    svg(
      <path d="M10 13a5 5 0 0 0 7 0l2-2a5 5 0 0 0-7-7l-1 1M14 11a5 5 0 0 0-7 0l-2 2a5 5 0 0 0 7 7l1-1" />,
    ),
  shield: () =>
    svg(<path d="M12 3l8 3v6c0 5-3.5 8-8 9-4.5-1-8-4-8-9V6l8-3z" />),
  bell: () =>
    svg(
      <path d="M6 9a6 6 0 1 1 12 0c0 5 2 6 2 6H4s2-1 2-6M10 20a2 2 0 0 0 4 0" />,
    ),
  plane: () =>
    svg(
      <path d="M10.5 13.5L3 12l1-2 4 .5 4-5 2 .5-2 5 4 .5 1.5-1.5 1.5.5-2 4 2 4-1.5.5L13 16l-2.5-2.5z" />,
    ),
} as const;

export type IconName = keyof typeof Icons;
