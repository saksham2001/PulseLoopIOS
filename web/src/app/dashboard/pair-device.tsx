"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { PulseCard, PulseButton } from "@/components/ui";

type PairedDevice = {
  id: string;
  name: string;
  pairedAt: string | null;
  lastSeenAt: string | null;
};

function relativeTime(iso: string | null): string {
  if (!iso) return "just now";
  const then = new Date(iso).getTime();
  const secs = Math.max(0, Math.round((Date.now() - then) / 1000));
  if (secs < 60) return "moments ago";
  const mins = Math.round(secs / 60);
  if (mins < 60) return `${mins} min ago`;
  const hrs = Math.round(mins / 60);
  if (hrs < 24) return `${hrs} hr ago`;
  const days = Math.round(hrs / 24);
  return `${days} day${days === 1 ? "" : "s"} ago`;
}

export function PairDevice() {
  const [code, setCode] = useState<string | null>(null);
  const [expiresAt, setExpiresAt] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [devices, setDevices] = useState<PairedDevice[] | null>(null);
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const fetchDevices = useCallback(async (): Promise<PairedDevice[]> => {
    try {
      const res = await fetch("/api/devices", { cache: "no-store" });
      if (!res.ok) return [];
      const data = await res.json();
      const list: PairedDevice[] = data.devices ?? [];
      setDevices(list);
      return list;
    } catch {
      return [];
    }
  }, []);

  // Reflect existing pairing on load. This intentionally syncs server state into
  // React on mount; the setState happens asynchronously inside fetchDevices after
  // the network call, not synchronously in the effect body.
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void fetchDevices();
  }, [fetchDevices]);

  // While a code is shown, poll for the device redeeming it so the UI flips to
  // "connected" live without a manual refresh.
  useEffect(() => {
    if (!code) return;
    pollRef.current = setInterval(async () => {
      const list = await fetchDevices();
      if (list.length > 0) {
        setCode(null);
        setExpiresAt(null);
        if (pollRef.current) clearInterval(pollRef.current);
      }
    }, 2500);
    return () => {
      if (pollRef.current) clearInterval(pollRef.current);
    };
  }, [code, fetchDevices]);

  async function generate() {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch("/api/devices/pair", { method: "POST" });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();
      setCode(data.code);
      setExpiresAt(data.expiresAt);
    } catch {
      setError("Couldn't generate a code. Try again.");
    } finally {
      setLoading(false);
    }
  }

  const isPaired = (devices?.length ?? 0) > 0;

  // Connected state: a device is paired and no fresh code is being shown.
  if (isPaired && !code) {
    const primary = devices![0];
    return (
      <PulseCard>
        <div className="flex items-start justify-between gap-4">
          <div>
            <div className="flex items-center gap-2">
              <span className="bg-success h-2.5 w-2.5 rounded-full" />
              <h2 className="text-text-primary font-serif text-[22px]">
                iPhone connected
              </h2>
            </div>
            <p className="text-text-secondary mt-1 text-[15px]">
              {primary.name} is paired and syncing to web.
            </p>
            <p className="text-text-muted mt-1 text-xs">
              Last synced {relativeTime(primary.lastSeenAt ?? primary.pairedAt)}
            </p>
          </div>
        </div>
        <button
          onClick={generate}
          disabled={loading}
          className="text-text-secondary mt-4 block text-sm underline-offset-2 hover:underline disabled:opacity-50"
        >
          Pair another device
        </button>
        {error && <p className="text-alert mt-3 text-sm">{error}</p>}
      </PulseCard>
    );
  }

  return (
    <PulseCard>
      <h2 className="text-text-primary font-serif text-[22px]">
        Pair your iPhone
      </h2>
      <p className="text-text-secondary mt-1 text-[15px]">
        Generate a code, then enter it in the PulseLoop app under Settings →
        Connect to web.
      </p>

      {code ? (
        <div className="mt-4 space-y-3">
          <div className="bg-fill-subtle text-text-primary inline-flex items-center gap-3 rounded-[12px] px-5 py-4 font-mono text-3xl tracking-[0.3em]">
            {code}
          </div>
          {expiresAt && (
            <p className="text-text-muted text-xs">
              Expires {new Date(expiresAt).toLocaleTimeString()}
            </p>
          )}
          <div className="text-text-muted flex items-center gap-2 text-sm">
            <span className="border-text-muted/40 border-t-text-secondary inline-block h-3.5 w-3.5 animate-spin rounded-full border-2" />
            Waiting for your iPhone to enter the code…
          </div>
          <button
            onClick={generate}
            disabled={loading}
            className="text-text-secondary block text-sm underline-offset-2 hover:underline disabled:opacity-50"
          >
            Generate a new code
          </button>
        </div>
      ) : (
        <PulseButton onClick={generate} disabled={loading} className="mt-4">
          {loading ? "Generating…" : "Generate pairing code"}
        </PulseButton>
      )}

      {error && <p className="text-alert mt-3 text-sm">{error}</p>}
    </PulseCard>
  );
}
