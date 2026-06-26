import { redirect } from "next/navigation";

// The dashboard has been superseded by the workspace Home screen. Pairing and
// metrics now live in the shell (Connect + Tracker). Keep the route as a
// redirect so old links and Clerk's default post-auth target resolve.
export default function DashboardPage() {
  redirect("/home");
}
