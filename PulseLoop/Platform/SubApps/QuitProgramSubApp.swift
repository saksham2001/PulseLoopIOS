import SwiftUI
import SwiftData

// MARK: - Quit Program SubApp (habit cessation / tapering)
//
// Migrated built-in (roadmap B14). Backed by the legacy `AppModule.quitProgram`
// module. Owns the `Vice` + `ViceLog` models and the quit-program screens.

struct QuitProgramSubApp: SubApp {
    var id: SubAppID { SubAppID(AppModule.quitProgram.rawValue) }
    var displayName: String { AppModule.quitProgram.name }
    var iconSystemName: String { AppModule.quitProgram.icon }
    var summary: String { AppModule.quitProgram.description }
    var origin: SubAppOrigin { .builtIn }

    var models: [any PersistentModel.Type] { [Vice.self, ViceLog.self] }

    var permissions: Set<SubAppPermission> { [.notifications] }

    func aiTools(flags: CoachFeatureFlags) -> [AnyCoachTool] {
        var tools = QuitProgramTools.readTools
        if flags.writeToolsEnabled { tools += QuitProgramTools.writeTools }
        return tools
    }
}

// MARK: - Quit Program Coach Tools
//
// Read + write for the habit-cessation module (`Vice` / `ViceLog`). Reads list
// the user's quit goals with streaks and money saved; writes log relapses,
// resisted urges, and triggers. All writes are additive logs → apply immediately.
@MainActor
enum QuitProgramTools {
    static var readTools: [AnyCoachTool] { [listVices] }
    static var writeTools: [AnyCoachTool] { [logViceEvent] }

    private static func vices(_ ctx: ToolExecutionContext) -> [Vice] {
        (try? ctx.modelContext.fetch(FetchDescriptor<Vice>())) ?? []
    }

    private static var listVices: AnyCoachTool {
        .make(
            name: "list_quit_goals",
            label: "Reviewing your quit goals",
            description: "List the user's quit/taper goals (vices) with current streak (days), longest streak, money saved, and quit date. Returns ids for log_quit_event.",
            parameters: JSONSchema.empty,
            argsType: NoArgs.self
        ) { _, ctx in
            let rows = vices(ctx).filter { $0.isActive }.map { v -> [String: Any] in
                ["id": v.id.uuidString, "name": v.name, "current_streak_days": v.currentStreak,
                 "longest_streak_days": v.longestStreak, "money_saved": v.moneySaved,
                 "taper": v.taperScheduleRaw]
            }
            return .object(["quit_goals": rows, "count": rows.count])
        }
    }

    private struct LogEventArgs: Decodable {
        let goalId: String
        let type: String
        let triggerContext: String?
        let intensity: Int?
        let copingUsed: String?
        let notes: String?
        enum CodingKeys: String, CodingKey {
            case goalId = "goal_id", type, triggerContext = "trigger_context",
                 intensity, copingUsed = "coping_used", notes
        }
    }

    private static var logViceEvent: AnyCoachTool {
        .make(
            name: "log_quit_event",
            label: "Logging a quit event",
            description: "Log an event for a quit goal. type: relapse, urge_resisted, or trigger. Optionally capture trigger_context, intensity (1–10), coping_used, and notes. A relapse resets the streak. Applies immediately.",
            parameters: JSONSchema.object([
                "goal_id": JSONSchema.string,
                "type": JSONSchema.enumString(["relapse", "urge_resisted", "trigger"]),
                "trigger_context": ["type": ["string", "null"]],
                "intensity": ["type": ["integer", "null"]],
                "coping_used": ["type": ["string", "null"]],
                "notes": ["type": ["string", "null"]],
            ], required: ["goal_id", "type", "trigger_context", "intensity", "coping_used", "notes"]),
            argsType: LogEventArgs.self
        ) { args, ctx in
            guard let id = UUID(uuidString: args.goalId),
                  let vice = vices(ctx).first(where: { $0.id == id }) else {
                return .error("quit goal '\(args.goalId)' not found. Call list_quit_goals.")
            }
            let type: ViceLogType
            switch args.type {
            case "relapse": type = .relapse
            case "trigger": type = .triggerLogged
            default: type = .urgeResisted
            }
            let log = ViceLog(viceId: id, type: type,
                              triggerContext: args.triggerContext,
                              intensity: args.intensity.map { min(10, max(1, $0)) } ?? 5,
                              copingUsed: args.copingUsed, notes: args.notes)
            ctx.modelContext.insert(log)
            vice.logs.append(log)
            ctx.modelContext.saveOrLog("subapp.quit")
            return .object(["ok": true, "logged": true, "goal": vice.name, "type": type.rawValue,
                            "current_streak_days": vice.currentStreak])
        }
    }
}
