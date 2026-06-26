# Bugfix Open Loop

Goal: drive the PulseLoop app to a green, bug-free state. Run this loop until no
bugs remain, proceeding autonomously on every iteration (no permission asks).

## Loop

1. **Detect** — gather signal, in priority order:
   - `xcodebuild -scheme PulseLoop -destination 'platform=iOS Simulator,id=<booted>' build` → fix every `error:`.
   - `xcodebuild test ...` → collect every failing `Test Case`.
   - Static read of the uncommitted diff (`git diff`) and new files for logic bugs:
     force-unwraps, array index OOB, actor/concurrency misuse, retain cycles,
     wrong comparisons, off-by-one, unhandled optionals, dead code paths,
     mis-wired bindings, duplicated state, broken navigation routes.
2. **Triage** — one task per distinct bug (TaskCreate). Order: build-breakers →
   test failures → crashers → logic/UX bugs → warnings that mask bugs.
3. **Fix** — smallest correct change that matches surrounding code style. No
   behavior regressions; preserve the no-em-dash / contract invariants.
4. **Verify** — rebuild; re-run the affected tests (or full suite at the end).
   A task is done only when build is green and its test passes.
5. **Repeat** until: build green, full test suite green, and a static pass over
   the diff surfaces no new defect. Then stop and summarize.

## Invariants (do not break)
- No em/en dashes in any user-facing or model-facing string.
- Coach response contract: chart only on `insight_with_chart`, non-empty summary.
- On-device + content-free telemetry/feedback.
- Modules are declarative specs, never code.

## Status
See `docs/LIFE_OS_PROGRESS.md` for feature context. Update task list as you go.
