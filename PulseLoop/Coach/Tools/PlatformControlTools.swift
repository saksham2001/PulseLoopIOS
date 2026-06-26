import Foundation
import SwiftData

// MARK: - Platform Control Coach Tools
//
// Gives the AI command palette authority over the whole app: read the module
// catalog, turn modules on/off, install a designed sub-app live, and create
// tasks/notes in any feature. Reversible changes (enabling a module, creating
// content, installing) apply immediately; destructive ones (disabling a module,
// uninstalling a user-created sub-app) return `needs_confirmation` and queue a
// `PendingAction` rendered as a Confirm/Cancel card.
//
// Gated by `flags.platformControlEnabled` (Settings → "Platform control").
@MainActor
enum PlatformControlTools {
    static var all: [AnyCoachTool] {
        [listModules, setModuleEnabled, removeModuleData, saveSubApp, uninstallSubApp,
         listModuleUpdates, updateModule, improveModule, createTask, createNote, navigateTo,
         listConnectedSources, listUpcomingEvents, listRecentMessages]
    }

    // MARK: list_modules

    private static var listModules: AnyCoachTool {
        .make(
            name: "list_modules",
            label: "Reviewing your modules",
            description: "List every module / sub-app in the app with its id, name, whether it's currently INSTALLED, and its origin (built_in, user_created, installed). No module comes standard — uninstalled modules are absent from the app (no tab, Home card, or tools). Call this before installing/uninstalling so you use the correct id.",
            parameters: JSONSchema.empty,
            argsType: NoArgs.self
        ) { _, _ in
            let registry = SubAppRegistry.shared
            let modules = registry.subApps.map { app -> [String: Any] in
                [
                    "id": app.id.rawValue,
                    "name": app.displayName,
                    "summary": app.summary,
                    "installed": registry.isInstalled(app.id),
                    "origin": app.origin.rawValue,
                ]
            }
            return .object(["modules": modules, "count": modules.count,
                            "installed_count": registry.installedIDs.count])
        }
    }

    // MARK: set_module_enabled (install / uninstall)

    private struct SetModuleArgs: Decodable {
        let moduleId: String
        let enabled: Bool
        let reason: String
        enum CodingKeys: String, CodingKey { case moduleId = "module_id", enabled, reason }
    }

    private static var setModuleEnabled: AnyCoachTool {
        .make(
            name: "set_module_enabled",
            label: "Updating your modules",
            description: "Install (enabled=true) or uninstall (enabled=false) a module/sub-app by id (from list_modules). Installing applies immediately and makes the module appear in tabs/Home/sidebar/tools. Uninstalling HIDES a feature (data is preserved and restored if reinstalled), so it returns needs_confirmation and shows a Confirm card; the change only happens after the user taps Confirm. Built-in modules can be uninstalled too.",
            parameters: JSONSchema.object([
                "module_id": JSONSchema.string,
                "enabled": JSONSchema.boolean,
                "reason": JSONSchema.string,
            ], required: ["module_id", "enabled", "reason"]),
            argsType: SetModuleArgs.self
        ) { args, ctx in
            let registry = SubAppRegistry.shared
            let id = SubAppID(args.moduleId)
            guard let app = registry.subApp(id: id) else {
                return .error("module '\(args.moduleId)' not found. Call list_modules for valid ids.")
            }

            if args.enabled {
                registry.install(id)
                return .object(["ok": true, "module_id": args.moduleId, "installed": true,
                                "applied": true, "name": app.displayName,
                                "note": "\(app.displayName) is now installed and visible across the app."])
            }

            // Uninstalling hides a feature → confirm (data is preserved).
            if !registry.isInstalled(id) {
                return .object(["ok": true, "module_id": args.moduleId, "installed": false,
                                "applied": true, "note": "\(app.displayName) is already uninstalled."])
            }
            ctx.pendingActions.append(PendingAction(
                kind: .disableModule,
                summary: "Uninstall \(app.displayName)? Its data is kept and restored if you reinstall.",
                confirmLabel: "Uninstall",
                platform: PlatformActionPayload(targetId: args.moduleId, displayName: app.displayName)
            ))
            return .object(["ok": true, "needs_confirmation": true,
                            "summary": "Awaiting your confirmation to uninstall \(app.displayName)."])
        }
    }

    // MARK: remove_module_data

    private struct RemoveModuleDataArgs: Decodable {
        let moduleId: String
        let reason: String
        enum CodingKeys: String, CodingKey { case moduleId = "module_id", reason }
    }

    private static var removeModuleData: AnyCoachTool {
        .make(
            name: "remove_module_data",
            label: "Removing a module and its data",
            description: "Uninstall a module/sub-app by id AND permanently delete its stored data. Unlike set_module_enabled(enabled=false) — which hides the module but keeps its data so reinstalling restores it — this wipes the data and cannot be undone. Always returns needs_confirmation and shows a Confirm card; the change only happens after the user taps Confirm. Use only when the user explicitly asks to delete the data too.",
            parameters: JSONSchema.object([
                "module_id": JSONSchema.string,
                "reason": JSONSchema.string,
            ], required: ["module_id", "reason"]),
            argsType: RemoveModuleDataArgs.self
        ) { args, ctx in
            let registry = SubAppRegistry.shared
            guard let app = registry.subApp(id: SubAppID(args.moduleId)) else {
                return .error("module '\(args.moduleId)' not found. Call list_modules for valid ids.")
            }
            ctx.pendingActions.append(PendingAction(
                kind: .removeModuleData,
                summary: "Uninstall \(app.displayName) AND permanently delete its data? This can't be undone.",
                confirmLabel: "Delete data",
                platform: PlatformActionPayload(targetId: args.moduleId, displayName: app.displayName)
            ))
            return .object(["ok": true, "needs_confirmation": true,
                            "summary": "Awaiting your confirmation to uninstall \(app.displayName) and erase its data."])
        }
    }

    // MARK: save_subapp

    private struct SaveSubAppArgs: Decodable {
        let reason: String
    }

    private static var saveSubApp: AnyCoachTool {
        .make(
            name: "save_subapp",
            label: "Preparing your sub-app",
            description: "Stage the currently designed sub-app (the draft from generate_subapp_spec / refine_subapp_spec) for installation. Call this AFTER generating or refining a spec. This does NOT install immediately: it shows the user a live preview and an Install/Cancel card, and the module is only created after they tap Install.",
            parameters: JSONSchema.object([
                "reason": JSONSchema.string,
            ], required: ["reason"]),
            argsType: SaveSubAppArgs.self
        ) { _, ctx in
            guard let draft = SubAppBuilderDraftStore.shared.draft else {
                return .error("no_draft: design a sub-app first with generate_subapp_spec, then call save_subapp.")
            }
            // Quality gate (defense in depth): never stage an install for a spec
            // that fails validation or guardrails. Surface the issues so the model
            // can refine rather than dead-end the user.
            let errors = SubAppSpecValidator.issues(in: draft).filter { $0.severity == .error }
            if !errors.isEmpty {
                let detail = errors.map { "\($0.path): \($0.message)" }.joined(separator: "; ")
                return .error("the draft is invalid; refine it before saving. Issues: \(detail)")
            }
            let report = SubAppGuardrails.review(draft)
            guard report.canSave else {
                let detail = report.blockers.map { $0.message }.joined(separator: "; ")
                return .error("the draft violates guardrails; refine it before saving. Issues: \(detail)")
            }
            // Queue an Install confirm card. The draft remains staged so the card
            // can render a live preview; the executor commits it on Confirm.
            let permissionNote = draft.permissions.isEmpty
                ? ""
                : " It requests: \(draft.permissions.map { $0.rawValue }.joined(separator: ", "))."
            ctx.pendingActions.append(PendingAction(
                kind: .installSubApp,
                summary: "Install \(draft.displayName)?\(permissionNote)",
                confirmLabel: "Install",
                platform: PlatformActionPayload(targetId: draft.id, displayName: draft.displayName)
            ))
            return .object([
                "ok": true,
                "needs_confirmation": true,
                "module_id": draft.id,
                "name": draft.displayName,
                "note": "Showing \(draft.displayName) as a preview with an Install card. It will be installed and opened only after the user taps Install.",
            ])
        }
    }

    // MARK: uninstall_subapp

    private struct UninstallArgs: Decodable {
        let moduleId: String
        let reason: String
        enum CodingKeys: String, CodingKey { case moduleId = "module_id", reason }
    }

    private static var uninstallSubApp: AnyCoachTool {
        .make(
            name: "uninstall_subapp",
            label: "Removing a sub-app",
            description: "Permanently delete a user-created sub-app by id. Built-in modules cannot be uninstalled (disable them instead). Always returns needs_confirmation and shows a Confirm card; deletion only happens after the user taps Confirm.",
            parameters: JSONSchema.object([
                "module_id": JSONSchema.string,
                "reason": JSONSchema.string,
            ], required: ["module_id", "reason"]),
            argsType: UninstallArgs.self
        ) { args, ctx in
            let registry = SubAppRegistry.shared
            guard let app = registry.subApp(id: SubAppID(args.moduleId)) else {
                return .error("module '\(args.moduleId)' not found.")
            }
            guard app.origin == .userCreated || app.origin == .installed else {
                return .error("'\(app.displayName)' is a built-in module and can't be uninstalled. Disable it with set_module_enabled instead.")
            }
            ctx.pendingActions.append(PendingAction(
                kind: .uninstallSubApp,
                summary: "Permanently delete the \(app.displayName) sub-app? This can't be undone.",
                confirmLabel: "Delete",
                platform: PlatformActionPayload(targetId: args.moduleId, displayName: app.displayName)
            ))
            return .object(["ok": true, "needs_confirmation": true,
                            "summary": "Awaiting your confirmation to uninstall \(app.displayName)."])
        }
    }

    // MARK: list_module_updates

    private static var listModuleUpdates: AnyCoachTool {
        .make(
            name: "list_module_updates",
            label: "Checking for module updates",
            description: "List installed modules that have a newer version available, with their id, name, installed version, and the available version. Returns an empty list if everything is up to date. Call before update_module so you use the correct id.",
            parameters: JSONSchema.empty,
            argsType: NoArgs.self
        ) { _, _ in
            let registry = SubAppRegistry.shared
            let rows = registry.modulesWithUpdates.map { app -> [String: Any] in
                let installed = registry.installedVersion(of: app.id)
                return [
                    "id": app.id.rawValue,
                    "name": app.displayName,
                    "installed_version": installed.map { "\($0)" } ?? "unknown",
                    "available_version": "\(app.semanticVersion)",
                    "needs_confirmation": registry.updateNeedsConfirmation(app.id),
                ]
            }
            return .object(["updates": rows, "count": rows.count])
        }
    }

    // MARK: update_module

    private struct UpdateModuleArgs: Decodable {
        let moduleId: String
        let reason: String
        enum CodingKeys: String, CodingKey { case moduleId = "module_id", reason }
    }

    private static var updateModule: AnyCoachTool {
        .make(
            name: "update_module",
            label: "Updating a module",
            description: "Update an installed module to its latest available version by id (from list_module_updates). Most updates apply immediately. Updates that run a data migration the module flags as risky return needs_confirmation and show a Confirm card; the update only happens after the user taps Confirm.",
            parameters: JSONSchema.object([
                "module_id": JSONSchema.string,
                "reason": JSONSchema.string,
            ], required: ["module_id", "reason"]),
            argsType: UpdateModuleArgs.self
        ) { args, ctx in
            let registry = SubAppRegistry.shared
            let id = SubAppID(args.moduleId)
            guard let app = registry.subApp(id: id) else {
                return .error("module '\(args.moduleId)' not found. Call list_modules for valid ids.")
            }
            guard let available = registry.availableUpdate(for: id) else {
                return .object(["ok": true, "module_id": args.moduleId, "applied": true,
                                "note": "\(app.displayName) is already up to date."])
            }
            if registry.updateNeedsConfirmation(id) {
                ctx.pendingActions.append(PendingAction(
                    kind: .updateModule,
                    summary: "Update \(app.displayName) to v\(available)? This runs a data migration.",
                    confirmLabel: "Update",
                    platform: PlatformActionPayload(targetId: args.moduleId, displayName: app.displayName)
                ))
                return .object(["ok": true, "needs_confirmation": true,
                                "summary": "Awaiting your confirmation to update \(app.displayName) to v\(available)."])
            }
            guard let applied = registry.applyUpdate(id, context: ctx.modelContext) else {
                return .object(["ok": true, "module_id": args.moduleId, "applied": true,
                                "note": "\(app.displayName) is already up to date."])
            }
            return .object(["ok": true, "module_id": args.moduleId, "applied": true,
                            "version": "\(applied)", "name": app.displayName,
                            "note": "\(app.displayName) updated to v\(applied)."])
        }
    }

    // MARK: improve_module

    private struct ImproveModuleArgs: Decodable {
        let moduleId: String
        let reason: String
        enum CodingKeys: String, CodingKey { case moduleId = "module_id", reason }
    }

    private static var improveModule: AnyCoachTool {
        .make(
            name: "improve_module",
            label: "Improving a module",
            description: "Propose a safe, additive improvement to an installed user-created or installed sub-app by id (from list_modules). The improvement agent suggests a better version as a spec diff (e.g. add a Notes field, add an Overview dashboard, or repair a validation issue). This NEVER edits the live module directly: it shows the user the proposed change with an Apply/Cancel card and only applies after they confirm. Use when the user asks to improve, enhance, or fix one of their modules.",
            parameters: JSONSchema.object([
                "module_id": JSONSchema.string,
                "reason": JSONSchema.string,
            ], required: ["module_id", "reason"]),
            argsType: ImproveModuleArgs.self
        ) { args, ctx in
            let registry = SubAppRegistry.shared
            let id = SubAppID(args.moduleId)
            guard let app = registry.subApp(id: id) else {
                return .error("module '\(args.moduleId)' not found. Call list_modules for valid ids.")
            }
            guard app.origin == .userCreated || app.origin == .installed else {
                return .error("'\(app.displayName)' is a built-in module; the improvement agent only refines user-created or installed modules.")
            }
            guard let spec = UserSubAppStore.shared.specs.first(where: { $0.id == args.moduleId }) else {
                return .error("'\(app.displayName)' isn't a declarative module the agent can improve.")
            }
            guard let proposal = ModuleImprovementAgent.propose(for: spec) else {
                return .object(["ok": true, "has_improvement": false,
                                "note": "\(app.displayName) already looks good — no safe improvement to propose right now."])
            }
            ModuleImprovementStore.shared.stage(proposal)
            ctx.pendingActions.append(PendingAction(
                kind: .applyModuleImprovement,
                summary: "Improve \(app.displayName)? \(proposal.rationale)\(proposal.isBreaking ? " (may change stored data)" : "")",
                confirmLabel: "Apply",
                platform: PlatformActionPayload(targetId: args.moduleId, displayName: app.displayName)
            ))
            return .object([
                "ok": true,
                "needs_confirmation": true,
                "has_improvement": true,
                "module_id": args.moduleId,
                "name": app.displayName,
                "is_breaking": proposal.isBreaking,
                "rationale": proposal.rationale,
                "note": "Proposed an improvement to \(app.displayName) with an Apply card. It will only be applied after the user taps Apply.",
            ])
        }
    }

    // MARK: create_task

    private struct CreateTaskArgs: Decodable {
        let title: String
        let group: String?
        let dueDate: String?
        enum CodingKeys: String, CodingKey { case title, group, dueDate = "due_date" }
    }

    // MARK: list_connected_sources / list_upcoming_events / list_recent_messages

    private static var listConnectedSources: AnyCoachTool {
        .make(
            name: "list_connected_sources",
            label: "Checking connected sources",
            description: "List which wearables (Fitbit, Google Fit, Oura, Whoop, Garmin) and accounts (Gmail, Google/Apple Calendar, Slack, Notion, Todoist) the user has connected, plus each one's last sync time. Use this to know what live data you can reference.",
            parameters: JSONSchema.empty,
            argsType: NoArgs.self
        ) { _, _ in
            let wearables = WearableConnectionManager.shared
            let accounts = AccountConnectionManager.shared
            let wearableRows = WearableProvider.allCases
                .filter { wearables.isConnected($0) }
                .map { p -> [String: Any] in
                    var row: [String: Any] = ["id": p.rawValue, "name": p.displayName, "kind": "wearable"]
                    if let ts = wearables.lastSyncedAt[p] { row["last_sync"] = ISO8601DateFormatter().string(from: ts) }
                    return row
                }
            let accountProviders: [AccountProvider] = [.gmail, .googleCalendar, .appleCalendar, .slack, .notion, .todoist]
            let accountRows = accountProviders
                .filter { accounts.isConnected($0) }
                .map { p -> [String: Any] in
                    var row: [String: Any] = ["id": p.rawValue, "name": p.rawValue.capitalized, "kind": "account"]
                    if let ts = accounts.lastSyncedAt[p] { row["last_sync"] = ISO8601DateFormatter().string(from: ts) }
                    return row
                }
            let all = wearableRows + accountRows
            return .object([
                "connected": all,
                "count": all.count,
                "note": all.isEmpty ? "Nothing connected yet. The user can link sources in Connect." : "These sources are live; their data already flows into the dashboard and inbox.",
            ])
        }
    }

    private static var listUpcomingEvents: AnyCoachTool {
        .make(
            name: "list_upcoming_events",
            label: "Checking your calendar",
            description: "List upcoming calendar events the user has synced from Google or Apple Calendar (they land in the inbox as calendar items). Read-only. To add or change an event, propose it and let the user confirm — never write silently.",
            parameters: JSONSchema.empty,
            argsType: NoArgs.self
        ) { _, ctx in
            let descriptor = FetchDescriptor<InboxItem>()
            let items = ((try? ctx.modelContext.fetch(descriptor)) ?? [])
                .filter { $0.source == .calendar && !$0.isHandled }
                .sorted { $0.receivedAt > $1.receivedAt }
                .prefix(20)
            let events = items.map { item -> [String: Any] in
                ["title": item.title, "when": Self.stripMarker(item.subtitle)]
            }
            return .object(["events": Array(events), "count": events.count])
        }
    }

    private static var listRecentMessages: AnyCoachTool {
        .make(
            name: "list_recent_messages",
            label: "Checking your messages",
            description: "List recent messages/receipts the user has synced from Gmail or Slack (they land in the inbox). Read-only. To reply or post, propose it and let the user confirm — never send silently.",
            parameters: JSONSchema.empty,
            argsType: NoArgs.self
        ) { _, ctx in
            let descriptor = FetchDescriptor<InboxItem>()
            let items = ((try? ctx.modelContext.fetch(descriptor)) ?? [])
                .filter { ($0.source == .gmail || $0.source == .slack) && !$0.isHandled }
                .sorted { $0.receivedAt > $1.receivedAt }
                .prefix(20)
            let messages = items.map { item -> [String: Any] in
                ["source": item.source.rawValue, "title": item.title, "preview": Self.stripMarker(item.subtitle)]
            }
            return .object(["messages": Array(messages), "count": messages.count])
        }
    }

    /// Strip the internal `#evt:…` / `#msg:…` de-dupe marker from a synced inbox
    /// subtitle so the assistant never sees or repeats it.
    private static func stripMarker(_ subtitle: String) -> String {
        guard let range = subtitle.range(of: "#") else { return subtitle }
        return String(subtitle[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
    }

    // MARK: create_task

    private static var createTask: AnyCoachTool {
        .make(
            name: "create_task",
            label: "Adding a task",
            description: "Create a to-do task. Optionally set a group/project and a due date (ISO yyyy-MM-dd). Applies immediately.",
            parameters: JSONSchema.object([
                "title": JSONSchema.string,
                "group": ["type": ["string", "null"]],
                "due_date": ["type": ["string", "null"]],
            ], required: ["title", "group", "due_date"]),
            argsType: CreateTaskArgs.self
        ) { args, ctx in
            let title = args.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return .error("title is empty") }
            let due = args.dueDate.flatMap(CoachDataAccess.parseLocalDate)
            let item = TaskItem(
                title: title,
                group: (args.group?.isEmpty == false ? args.group! : "Inbox"),
                dueDate: due
            )
            ctx.modelContext.insert(item)
            ctx.modelContext.saveOrLog("coach.platform")
            return .object(["ok": true, "created": true, "task_id": item.id.uuidString,
                            "title": title, "group": item.group])
        }
    }

    // MARK: create_note

    private struct CreateNoteArgs: Decodable {
        let title: String
        let body: String
    }

    private static var createNote: AnyCoachTool {
        .make(
            name: "create_note",
            label: "Saving a note",
            description: "Create a note. `body` may contain multiple lines; each non-empty line becomes a paragraph block. Applies immediately.",
            parameters: JSONSchema.object([
                "title": JSONSchema.string,
                "body": JSONSchema.string,
            ], required: ["title", "body"]),
            argsType: CreateNoteArgs.self
        ) { args, ctx in
            let title = args.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty || !args.body.isEmpty else { return .error("note is empty") }
            let note = Note(title: title.isEmpty ? "Note" : title)
            ctx.modelContext.insert(note)
            let lines = args.body
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            for (i, line) in lines.enumerated() {
                let block = NoteBlock(noteId: note.id, order: i, kind: .paragraph, content: line)
                ctx.modelContext.insert(block)
                note.blocks.append(block)
            }
            ctx.modelContext.saveOrLog("coach.platform")
            return .object(["ok": true, "created": true, "note_id": note.id.uuidString,
                            "title": note.title, "block_count": lines.count])
        }
    }

    // MARK: navigate_to

    private struct NavigateArgs: Decodable {
        let destination: String
        let reason: String
        /// Optional UUID used when `destination == "trip"` to open a specific trip's
        /// itinerary (the id returned by `create_trip`/`list_trips`).
        let tripId: String?
        enum CodingKeys: String, CodingKey { case destination, reason, tripId = "trip_id" }
    }

    /// Stable destination keys the model can target. Maps to an `AppRoute` and/or a
    /// `MainTab`. Keep these names human/AI-friendly and in sync with the schema enum.
    private static let destinations: [String: (tab: MainTab?, route: AppRoute?)] = [
        "home": (.home, nil),
        "tracker": (.tracker, nil),
        "inbox": (.inbox, nil),
        "friends": (.friends, nil),
        "settings": (nil, .settings),
        "profile": (nil, .profile),
        "notes": (nil, .notesList),
        "tasks": (nil, .tasksList),
        "day_plan": (nil, .dayPlan),
        "travel": (nil, .travel),
        "health": (nil, .health),
        "vitals": (nil, .vitals),
        "sleep": (nil, .sleep),
        "activity": (nil, .activity),
        "fitness": (nil, .fitness),
        "insights": (nil, .insights),
        "journal": (nil, .journal),
        "knowledge_base": (nil, .knowledgeBase),
        "exercise_library": (nil, .exerciseLibrary),
        "workout_builder": (nil, .workoutBuilder),
        "modules": (nil, .modulePicker),
        "my_subapps": (nil, .mySubApps),
        "subapp_builder": (nil, .subAppBuilder),
        "connect_accounts": (nil, .connectAccounts),
    ]

    private static var navigateTo: AnyCoachTool {
        .make(
            name: "navigate_to",
            label: "Opening a screen",
            description: "Open a screen/module in the app for the user. Use after acting to show the result, or when the user asks to \"go to\"/\"open\"/\"show me\" a feature. The assistant closes and the destination opens. To open one specific trip's itinerary, pass destination='trip' with its trip_id (from create_trip/list_trips). Valid destinations: trip, \(destinations.keys.sorted().joined(separator: ", ")).",
            parameters: JSONSchema.object([
                "destination": JSONSchema.enumString(["trip"] + Array(destinations.keys.sorted())),
                "reason": JSONSchema.string,
                "trip_id": ["type": ["string", "null"]],
            ], required: ["destination", "reason", "trip_id"]),
            argsType: NavigateArgs.self
        ) { args, _ in
            let key = args.destination.lowercased().trimmingCharacters(in: .whitespaces)
            // Deep-link to a specific trip's itinerary.
            if key == "trip" {
                guard let id = args.tripId, let uuid = UUID(uuidString: id) else {
                    return .error("destination 'trip' requires a valid trip_id from create_trip/list_trips.")
                }
                CoachNavigation.shared.requestNavigation(route: .tripDetail(uuid))
                return .object(["ok": true, "navigated": true, "destination": "trip",
                                "note": "Opening the trip itinerary. The assistant is closing to show it."])
            }
            guard let dest = destinations[key] else {
                return .error("unknown destination '\(args.destination)'. Valid: trip, \(destinations.keys.sorted().joined(separator: ", ")).")
            }
            CoachNavigation.shared.requestNavigation(route: dest.route, tab: dest.tab)
            return .object(["ok": true, "navigated": true, "destination": key,
                            "note": "Opening \(key). The assistant is closing to show it."])
        }
    }
}
