# PulseLoop — Dead Ends Punch List

Audit of interactive controls that go nowhere. The finish-the-app loop (Phase C) walks this until empty. Source audit: explore agent pass over `PulseLoop/Views/` (68 files) + `PulseLoop/Platform/SubApps/` (18 files).

Build gate: `xcodebuild -project PulseLoop.xcodeproj -scheme PulseLoop -destination 'platform=iOS Simulator,id=CFAB47DC-4676-469B-AA5F-29EED5A93200' build`.

## Open dead ends

_All cleared as of iteration C1. See Resolved below._

## Resolved

| # | File | Control | Resolution |
|---|---|---|---|
| 1 | `Views/TodayView.swift` | "Ask Assistant" | Wired to `CoachNavigation.shared.askAI("")`; also fixed `.system` font → `PulseFont` + inverse color |
| 2 | `Views/PrivacyPermissionsView.swift` | "View activity log" | Presents new `PrivacyActivityLogView` (designed, honest empty state) |
| 3 | `Views/PrivacyPermissionsView.swift` | "Export / delete all data" | Presents real `PrivacyDataSettingsSection` (export + delete) in a sheet |
| 4 | `Views/ProfileView.swift` | "Invite Members" | Presents `ShareSheet` with invite link |
| 5 | `Views/MessengerView.swift` | Compose button | Presents `ChatThreadView` new-message sheet |
| 6 | `Views/MessengerView.swift` | Send button | `sendMessage()` appends to local `messages` state; trims/guards empty |
| 7 | `Views/FriendsView.swift` | "Share invite link" | Presents `ShareSheet` with invite text |
| 8 | `Views/NoteEditorView.swift` | Menu "Settings" | Navigates to `AppRoute.settings` (relabeled "Voice & capture settings") |
| 9 | `Views/VitalsView.swift` | "HRV" coming-soon | Redesigned as `DetailCard` "Calibrating" state with explanation (design-system compliant) |
| 10 | `Views/VitalsView.swift` | "Skin temperature" coming-soon | Same |

Bonus: replaced 4 emoji icons (✉︎📅💬🏦) in `PrivacyPermissionsView` `PermissionRow` with SF Symbols.

## Cleared (verified NOT dead ends)
- `Components.swift` `action: {}` are inside `#Preview` only.
- `SleepSubApp.swift` L58 button has a real `path.append(AppRoute.sleep)`.
- ~40 `.disabled(...)` calls are all dynamic-state-bound; no permanent `.disabled(true)`.
- No print/haptic-only actions, stub view bodies, or TODO-bound controls.
- `Platform/SubApps/` is entirely clean.
