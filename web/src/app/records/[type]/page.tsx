import { UserButton } from "@clerk/nextjs";
import Link from "next/link";
import { notFound } from "next/navigation";
import { getOrCreateCurrentUser } from "@/lib/auth";
import { PulseTitle } from "@/components/ui";
import { recordTypeConfig } from "@/lib/record-types";
import { RecordsPanel } from "./records-panel";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ type: string }>;
}) {
  const { type } = await params;
  const cfg = recordTypeConfig(type);
  return { title: cfg ? `${cfg.title} — PulseLoop` : "PulseLoop" };
}

export default async function RecordsPage({
  params,
}: {
  params: Promise<{ type: string }>;
}) {
  const { type } = await params;
  const cfg = recordTypeConfig(type);
  if (!cfg) notFound();

  await getOrCreateCurrentUser();

  return (
    <div className="flex flex-1 flex-col">
      <header className="border-border-hairline bg-background flex items-center justify-between border-b px-5 py-4">
        <Link href="/dashboard" className="flex items-center gap-2">
          <span className="bg-success h-2 w-2 rounded-full" />
          <span className="font-serif text-[17px] tracking-tight">
            PulseLoop
          </span>
        </Link>
        <UserButton />
      </header>

      <main className="mx-auto w-full max-w-3xl flex-1 space-y-8 px-5 py-8">
        <section className="space-y-1">
          <PulseTitle className="text-3xl">
            {cfg.icon} {cfg.title}
          </PulseTitle>
          <p className="text-text-secondary text-[15px]">
            {cfg.description} Synced from your iPhone — use the feature in the
            app and it appears here.
          </p>
        </section>

        <RecordsPanel type={cfg.type} />
      </main>
    </div>
  );
}
