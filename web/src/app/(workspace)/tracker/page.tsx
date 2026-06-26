import { PageHeader } from "@/components/ui";
import { MetricsCards } from "@/components/workspace/metrics-cards";

export const metadata = { title: "Tracker — PulseLoop" };

export default function TrackerPage() {
  return (
    <div>
      <PageHeader
        title="Tracker"
        subtitle="Health data synced from your iPhone."
      />
      <div className="mt-7">
        <MetricsCards days={7} />
      </div>
    </div>
  );
}
