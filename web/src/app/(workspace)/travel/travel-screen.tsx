"use client";

import { useMemo, useState } from "react";
import { PageHeader, PulseCard, PulseChip } from "@/components/ui";
import { useRecords, type SyncRecord } from "@/components/workspace/use-records";

interface TripItemPayload {
  kind?: string;
  title?: string;
  details?: string;
  location?: string;
  url?: string;
  price?: number;
  currency?: string;
  rating?: number;
  dayOffset?: number;
  startAt?: string;
  booked?: boolean;
}

interface TripPayload {
  title?: string;
  status?: string;
  subtitle?: string;
  originCity?: string;
  startDate?: string;
  endDate?: string;
  notes?: string;
  travelerCount?: number;
  itemCount?: number;
  currency?: string;
  estimatedCost?: number;
  bookedCost?: number;
  budgetAmount?: number;
  items?: TripItemPayload[];
}

const KIND_ICON: Record<string, string> = {
  flight: "✈️",
  lodging: "🏨",
  activity: "🎟️",
  restaurant: "🍽️",
  transport: "🚆",
  note: "📝",
};

const STATUS_LABEL: Record<string, string> = {
  planning: "Planning",
  booked: "Booked",
  completed: "Completed",
  cancelled: "Cancelled",
};

// Status order for sectioning: active trips first, history last.
const STATUS_ORDER = ["planning", "booked", "completed", "cancelled"];

function money(amount: number | undefined, currency: string | undefined): string {
  if (amount === undefined || amount === null) return "";
  try {
    return new Intl.NumberFormat(undefined, {
      style: "currency",
      currency: currency || "USD",
      maximumFractionDigits: 0,
    }).format(amount);
  } catch {
    return `${Math.round(amount)} ${currency ?? ""}`.trim();
  }
}

function dateRange(start?: string, end?: string): string {
  if (!start) return "Dates TBD";
  const fmt = (iso: string) =>
    new Date(iso).toLocaleDateString(undefined, {
      month: "short",
      day: "numeric",
      year: "numeric",
    });
  if (!end) return fmt(start);
  const s = new Date(start);
  const e = new Date(end);
  const sameYear = s.getFullYear() === e.getFullYear();
  const shortStart = sameYear
    ? new Date(start).toLocaleDateString(undefined, { month: "short", day: "numeric" })
    : fmt(start);
  return `${shortStart} – ${fmt(end)}`;
}

function TripCard({ trip }: { trip: SyncRecord<TripPayload> }) {
  const [expanded, setExpanded] = useState(false);
  const p = trip.payload;
  const currency = p.currency || "USD";
  const items = p.items ?? [];
  const budget = p.budgetAmount;
  const spent = p.estimatedCost ?? 0;
  const overBudget = budget !== undefined && spent > budget;

  return (
    <PulseCard padding="p-0" className="overflow-hidden">
      <button
        type="button"
        onClick={() => setExpanded((v) => !v)}
        className="flex w-full items-start gap-4 p-5 text-left"
        aria-expanded={expanded}
      >
        <div className="bg-fill-subtle flex h-12 w-12 shrink-0 items-center justify-center rounded-[12px] text-[22px]">
          ✈️
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex flex-wrap items-center gap-2">
            <span className="text-text-primary text-[17px] font-semibold">
              {p.title || "Untitled trip"}
            </span>
            <PulseChip>{STATUS_LABEL[p.status ?? ""] ?? p.status ?? "Planning"}</PulseChip>
          </div>
          <div className="text-text-muted mt-1 text-[13.5px]">
            {p.originCity ? `${p.originCity} → ${p.title}  ·  ` : ""}
            {dateRange(p.startDate, p.endDate)}
            {p.travelerCount && p.travelerCount > 1
              ? `  ·  ${p.travelerCount} travelers`
              : ""}
          </div>
        </div>
        <div className="shrink-0 text-right">
          {budget !== undefined ? (
            <div className={`text-[15px] font-semibold ${overBudget ? "text-alert" : ""}`}>
              {money(spent, currency)}
              <span className="text-text-muted font-normal"> / {money(budget, currency)}</span>
            </div>
          ) : (
            <div className="text-[15px] font-semibold">{money(spent, currency)}</div>
          )}
          <div className="text-text-muted text-[12.5px]">
            {items.length} {items.length === 1 ? "plan" : "plans"}
          </div>
        </div>
      </button>

      {expanded && (
        <div className="border-border-hairline border-t px-5 py-4">
          {budget !== undefined && (
            <div className="mb-4">
              <div className="bg-fill-subtle h-2 w-full overflow-hidden rounded-full">
                <div
                  className={`h-full rounded-full ${overBudget ? "bg-alert" : "bg-black dark:bg-white"}`}
                  style={{ width: `${Math.min(100, budget > 0 ? (spent / budget) * 100 : 0)}%` }}
                />
              </div>
              <div className="text-text-muted mt-1.5 text-[12.5px]">
                {money(p.bookedCost, currency)} booked · {money(spent, currency)} planned ·{" "}
                {money(budget, currency)} budget
              </div>
            </div>
          )}

          {items.length === 0 ? (
            <p className="text-text-muted text-[14px]">No itinerary items yet.</p>
          ) : (
            <ul className="flex flex-col gap-2.5">
              {items.map((it, i) => (
                <li key={i} className="flex items-start gap-3">
                  <span className="mt-0.5 w-5 shrink-0 text-center text-[15px]">
                    {KIND_ICON[it.kind ?? "note"] ?? "•"}
                  </span>
                  <div className="min-w-0 flex-1">
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="text-[14.5px] font-medium">{it.title || "Untitled"}</span>
                      {it.booked && (
                        <span className="bg-accent/10 text-accent rounded-[6px] px-1.5 py-0.5 text-[11px] font-semibold">
                          Booked
                        </span>
                      )}
                      {it.rating !== undefined && (
                        <span className="text-text-muted text-[12px]">★ {it.rating.toFixed(1)}</span>
                      )}
                    </div>
                    {(it.location || it.details) && (
                      <div className="text-text-muted text-[12.5px]">
                        {it.location}
                        {it.location && it.details ? " · " : ""}
                        {it.details}
                      </div>
                    )}
                    {it.url && (
                      <a
                        href={it.url}
                        target="_blank"
                        rel="noreferrer"
                        className="text-accent text-[12.5px] underline-offset-2 hover:underline"
                      >
                        View booking
                      </a>
                    )}
                  </div>
                  {it.price !== undefined && (
                    <span className="text-text-secondary shrink-0 text-[13.5px] font-medium">
                      {money(it.price, it.currency || currency)}
                    </span>
                  )}
                </li>
              ))}
            </ul>
          )}

          {p.notes && (
            <p className="text-text-muted mt-4 text-[13.5px] italic">{p.notes}</p>
          )}
        </div>
      )}
    </PulseCard>
  );
}

export function TravelScreen() {
  const { records, loading, error } = useRecords<TripPayload>("trip");

  const grouped = useMemo(() => {
    const map = new Map<string, SyncRecord<TripPayload>[]>();
    for (const r of records ?? []) {
      const status = r.payload.status ?? "planning";
      const arr = map.get(status) ?? [];
      arr.push(r);
      map.set(status, arr);
    }
    // Sort each group by start date (soonest first for upcoming, newest first for done).
    for (const [status, arr] of map) {
      arr.sort((a, b) => {
        const da = a.payload.startDate ? Date.parse(a.payload.startDate) : 0;
        const db = b.payload.startDate ? Date.parse(b.payload.startDate) : 0;
        return status === "completed" || status === "cancelled" ? db - da : da - db;
      });
    }
    return map;
  }, [records]);

  const total = records?.length ?? 0;

  return (
    <div>
      <PageHeader
        title="Travel"
        subtitle="Trips, itineraries and budgets synced from your phone."
      />

      {error && (
        <p className="text-alert mt-6 text-[14px]">{error}</p>
      )}

      {!error && loading && (
        <p className="text-text-muted mt-6 text-[14px]">Loading trips…</p>
      )}

      {!error && !loading && total === 0 && (
        <PulseCard className="mt-7 text-center">
          <div className="text-[28px]">✈️</div>
          <p className="text-text-primary mt-2 text-[15px] font-semibold">No trips yet</p>
          <p className="text-text-muted mx-auto mt-1 max-w-md text-[14px]">
            Plan a trip in the PulseLoop app or ask the coach to build an itinerary — it&apos;ll
            show up here automatically.
          </p>
        </PulseCard>
      )}

      {!error && !loading && total > 0 && (
        <div className="mt-7 flex flex-col gap-8">
          {STATUS_ORDER.filter((s) => grouped.has(s)).map((status) => (
            <section key={status}>
              <h2 className="text-text-muted mb-3 text-[12px] font-semibold tracking-[0.09em] uppercase">
                {STATUS_LABEL[status] ?? status} · {grouped.get(status)!.length}
              </h2>
              <div className="flex flex-col gap-3">
                {grouped.get(status)!.map((trip) => (
                  <TripCard key={trip.clientId} trip={trip} />
                ))}
              </div>
            </section>
          ))}
        </div>
      )}
    </div>
  );
}
