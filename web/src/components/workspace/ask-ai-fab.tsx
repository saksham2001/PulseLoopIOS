"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { Icons } from "./icons";

/** Fixed "Ask AI" launcher (hidden on the coach route itself), matching the
 * prototype's floating button. */
export function AskAiFab() {
  const pathname = usePathname();
  if (pathname.startsWith("/coach")) return null;
  return (
    <Link
      href="/coach"
      aria-label="Ask AI"
      className="bg-accent text-on-accent fixed right-8 bottom-8 z-40 flex h-[60px] w-[60px] items-center justify-center rounded-[18px] shadow-[0_8px_24px_rgba(0,0,0,0.22)]"
    >
      <Icons.sparkLg />
    </Link>
  );
}
