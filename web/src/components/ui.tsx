import type { ReactNode } from "react";

/**
 * Shared UI primitives mirroring the iOS PulseLoop design system
 * (see .cursor/rules/design-system.mdc). Calm, monochrome, hairline-bordered
 * cards; black primary buttons; Newsreader titles + Hanken body.
 */

type Cx = (string | false | null | undefined)[];
function cx(...parts: Cx): string {
  return parts.filter(Boolean).join(" ");
}

/** Hairline-bordered surface card. */
export function PulseCard({
  children,
  className,
  padding = "p-5",
}: {
  children: ReactNode;
  className?: string;
  padding?: string;
}) {
  return (
    <div
      className={cx(
        "bg-background border-border-hairline rounded-[14px] border",
        padding,
        className,
      )}
    >
      {children}
    </div>
  );
}

/** Serif title (Newsreader), used for greetings/headings. */
export function PulseTitle({
  children,
  className,
  as: Tag = "h1",
}: {
  children: ReactNode;
  className?: string;
  as?: "h1" | "h2" | "h3";
}) {
  return (
    <Tag
      className={cx(
        "text-text-primary font-serif font-normal tracking-tight",
        className,
      )}
    >
      {children}
    </Tag>
  );
}

/** Uppercase, tracked, muted section label. */
export function PulseSectionLabel({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <p className={cx("pulse-section-label", className)}>{children}</p>
  );
}

type ButtonVariant = "primary" | "secondary" | "destructive";

const buttonBase =
  "inline-flex h-11 items-center justify-center gap-2 rounded-[12px] px-4 text-[15px] font-semibold transition disabled:opacity-50 disabled:pointer-events-none";

const buttonVariants: Record<ButtonVariant, string> = {
  // Primary action = black fill (never accent), per design rule.
  primary: "bg-black text-white hover:bg-black/85 dark:bg-white dark:text-black",
  secondary:
    "bg-background text-text-secondary border-border-strong border hover:bg-fill-subtle",
  destructive:
    "bg-background text-alert border-border-strong border hover:bg-alert/5",
};

export function PulseButton({
  children,
  variant = "primary",
  className,
  ...props
}: {
  children: ReactNode;
  variant?: ButtonVariant;
} & React.ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button
      className={cx(buttonBase, buttonVariants[variant], className)}
      {...props}
    >
      {children}
    </button>
  );
}

/** Link styled as a button (for navigation). */
export function PulseLinkButton({
  children,
  href,
  variant = "primary",
  className,
}: {
  children: ReactNode;
  href: string;
  variant?: ButtonVariant;
  className?: string;
}) {
  return (
    <a
      href={href}
      className={cx(buttonBase, buttonVariants[variant], className)}
    >
      {children}
    </a>
  );
}

/** Small rounded chip/badge. */
export function PulseChip({
  children,
  className,
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <span
      className={cx(
        "bg-fill-subtle text-text-secondary inline-flex items-center rounded-[6px] px-2 py-0.5 text-[12px] font-medium",
        className,
      )}
    >
      {children}
    </span>
  );
}

/** Screen header: large Newsreader title + optional muted subtitle, matching the
 * web prototype's per-screen heading block. */
export function PageHeader({
  title,
  subtitle,
  action,
  className,
}: {
  title: ReactNode;
  subtitle?: ReactNode;
  action?: ReactNode;
  className?: string;
}) {
  return (
    <div
      className={cx(
        action ? "flex items-end justify-between gap-4" : undefined,
        className,
      )}
    >
      <div>
        <h1 className="text-text-primary m-0 font-serif text-[40px] leading-none font-normal tracking-tight">
          {title}
        </h1>
        {subtitle && (
          <p className="text-text-muted mt-2 text-[16px]">{subtitle}</p>
        )}
      </div>
      {action}
    </div>
  );
}
