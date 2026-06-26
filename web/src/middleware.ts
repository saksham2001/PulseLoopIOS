import { clerkMiddleware, createRouteMatcher } from "@clerk/nextjs/server";

// Pages that require a signed-in browser session. API routes are intentionally
// NOT listed here: each handler does its own auth (Clerk session for /api/metrics
// and /api/devices, device token for /api/ingest, pairing code for /api/pair) and
// returns a clean JSON 401/404 instead of middleware's HTML/404 protection.
const isProtectedRoute = createRouteMatcher([
  "/dashboard(.*)",
  "/coach(.*)",
  "/today(.*)",
  "/home(.*)",
  "/capture(.*)",
  "/notes(.*)",
  "/tasks(.*)",
  "/protocol(.*)",
  "/journal(.*)",
  "/tracker(.*)",
  "/sleep(.*)",
  "/fitness(.*)",
  "/nutrition(.*)",
  "/mood(.*)",
  "/insights(.*)",
  "/trends(.*)",
  "/accountability(.*)",
  "/profile(.*)",
  "/modules(.*)",
  "/connect(.*)",
  "/permissions(.*)",
  "/settings(.*)",
]);

export default clerkMiddleware(async (auth, req) => {
  if (isProtectedRoute(req)) {
    await auth.protect();
  }
});

export const config = {
  matcher: [
    // Skip Next internals and static files, run on everything else.
    "/((?!_next|[^?]*\\.(?:html?|css|js(?!on)|jpe?g|webp|png|gif|svg|ttf|woff2?|ico|csv|docx?|xlsx?|zip|webmanifest)).*)",
    "/(api|trpc)(.*)",
  ],
};
