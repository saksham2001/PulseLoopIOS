import Link from "next/link";
import { auth } from "@clerk/nextjs/server";
import { PulseTitle, PulseSectionLabel } from "@/components/ui";

export default async function Home() {
  const { userId } = await auth();

  return (
    <main className="flex flex-1 flex-col items-center justify-center gap-10 px-5 py-16 text-center">
      <div className="max-w-xl space-y-4">
        <PulseSectionLabel>PulseLoop</PulseSectionLabel>
        <PulseTitle className="text-5xl leading-[1.05] sm:text-6xl">
          Your health, everywhere.
        </PulseTitle>
        <p className="text-text-secondary mx-auto max-w-md text-[15px] leading-relaxed">
          The data your ring and phone collect, now on any device — web,
          Windows, Android.
        </p>
      </div>

      <div className="flex flex-wrap items-center justify-center gap-3">
        {userId ? (
          <Link
            href="/home"
            className="inline-flex h-11 items-center justify-center rounded-[12px] bg-black px-6 text-[15px] font-semibold text-white transition hover:bg-black/85"
          >
            Open workspace
          </Link>
        ) : (
          <>
            <Link
              href="/sign-up"
              className="inline-flex h-11 items-center justify-center rounded-[12px] bg-black px-6 text-[15px] font-semibold text-white transition hover:bg-black/85"
            >
              Get started
            </Link>
            <Link
              href="/sign-in"
              className="border-border-strong text-text-secondary hover:bg-fill-subtle inline-flex h-11 items-center justify-center rounded-[12px] border bg-transparent px-6 text-[15px] font-semibold transition"
            >
              Sign in
            </Link>
          </>
        )}
      </div>
    </main>
  );
}
