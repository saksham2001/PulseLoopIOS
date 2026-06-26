import Link from "next/link";

export const metadata = {
  title: "Privacy Policy — PulseLoop",
  description:
    "How PulseLoop collects, uses, stores, and lets you control your health data.",
};

const UPDATED = "June 23, 2026";

export default function PrivacyPolicy() {
  return (
    <main className="mx-auto w-full max-w-3xl flex-1 px-6 py-16">
      <p className="pulse-section-label">PulseLoop</p>
      <h1 className="text-text-primary font-serif mt-2 text-4xl sm:text-5xl">
        Privacy Policy
      </h1>
      <p className="text-text-muted mt-2 text-sm">Last updated: {UPDATED}</p>

      <div className="text-text-secondary mt-10 space-y-8 leading-relaxed">
        <section className="space-y-3">
          <h2 className="text-text-primary font-serif text-[22px]">Overview</h2>
          <p>
            PulseLoop helps you understand your health data from a connected ring,
            your phone&apos;s health data, and the features you use in the app. We
            designed PulseLoop to keep your data on your device by default. Data only
            leaves your device when you explicitly turn on cloud sync or use a feature
            that requires a network service (such as the AI coach).
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-text-primary font-serif text-[22px]">
            What we collect
          </h2>
          <ul className="list-disc space-y-2 pl-6">
            <li>
              <strong>Health &amp; activity data</strong> you record or import (e.g.
              heart rate, SpO₂, steps, sleep, workouts). This stays on your device
              unless you enable cloud sync.
            </li>
            <li>
              <strong>Account data</strong> if you create a web account: your email
              and a unique account id (via our authentication provider, Clerk).
            </li>
            <li>
              <strong>Device pairing</strong>: a random token that links your phone to
              your account so your synced data reaches the right place.
            </li>
            <li>
              <strong>AI coach content</strong>: when you chat with the coach, the
              messages and the relevant context you allow are sent to our AI provider
              to generate a response.
            </li>
            <li>
              <strong>Purchases</strong>: AI-credit purchases are processed by Apple.
              We receive the transaction needed to grant your credits; we never receive
              your full payment details.
            </li>
          </ul>
        </section>

        <section className="space-y-3">
          <h2 className="text-text-primary font-serif text-[22px]">
            How we use it
          </h2>
          <p>
            We use your data only to provide the app: to show your metrics, sync them
            across your devices when you opt in, power AI features you choose to use,
            and account for AI credits. We do not sell your data, and we do not use
            your health data for advertising.
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-text-primary font-serif text-[22px]">
            Consent &amp; control
          </h2>
          <p>
            Cloud sync is off until you explicitly consent in the app. You can turn it
            off at any time by disconnecting in <em>Settings → Connect to web</em>,
            which stops further uploads and revokes consent. You can export your data
            and delete your account and synced data from the app.
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-text-primary font-serif text-[22px]">
            Diagnostics &amp; analytics
          </h2>
          <p>
            Crash diagnostics and anonymous usage analytics are off until you opt in
            under <em>Settings → Privacy &amp; data</em>. When enabled, we collect
            content-free signals only — crash and hang reports (via Apple&apos;s
            MetricKit) and event names like &ldquo;export started&rdquo; — to find and
            fix problems. No health data, message content, or personal identifiers are
            ever included. You can turn this off at any time.
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-text-primary font-serif text-[22px]">
            Storage &amp; sharing
          </h2>
          <p>
            When you enable cloud sync, your data is stored with our infrastructure
            providers (database hosting and authentication) solely to operate the
            service. AI requests are processed by our AI provider to return a response.
            These providers process data on our behalf and are not permitted to use it
            for their own purposes.
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-text-primary font-serif text-[22px]">
            Your rights
          </h2>
          <p>
            You can access, export, and delete your data. Use the export and delete
            options in the app&apos;s Settings, or contact us and we will help. Deleting
            your account removes your synced data from our systems.
          </p>
        </section>

        <section className="space-y-3">
          <h2 className="text-text-primary font-serif text-[22px]">Contact</h2>
          <p>
            Questions about this policy or your data? Email{" "}
            <a
              className="text-text-primary underline underline-offset-2"
              href="mailto:privacy@pulseloop.app"
            >
              privacy@pulseloop.app
            </a>
            .
          </p>
        </section>
      </div>

      <div className="mt-12">
        <Link
          href="/"
          className="border-border-strong text-text-secondary hover:bg-fill-subtle inline-flex h-11 items-center rounded-[12px] border px-5 text-[15px] font-semibold transition"
        >
          ← Back to PulseLoop
        </Link>
      </div>
    </main>
  );
}
