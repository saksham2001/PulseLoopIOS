import Foundation
import SwiftData

// MARK: - Task Coach Tools
//
// Read + write access to the user's to-dos (`TaskItem`). Reads are always on;
// writes are gated by `flags.writeToolsEnabled`. Creating/updating/completing a
// task applies immediately; deleting routes through a `PendingAction` confirm
// card (kind `.deleteEntity`, entityType "task").
//
// Note: `create_task` already exists in `PlatformControlTools` (gated by platform
// control). These tools complete the CRUD surface and are registered alongside
// the other write tools.
@MainActor
enum TaskTools {
    static var readTools: [AnyCoachTool] { [listTasks, getTask] }
    static var writeTools: [AnyCoachTool] { [updateTask, completeTask, deleteTask] }

    private static let statusEnum = ["todo", "in_progress", "done", "cancelled"]

    private static func fetchAll(_ ctx: ToolExecutionContext) -> [TaskItem] {
        (try? ctx.modelContext.fetch(FetchDescriptor<TaskItem>())) ?? []
    }

    private static func dict(_ t: TaskItem) -> [String: Any] {
        var d: [String: Any] = [
            "id": t.id.uuidString,
            "title": t.title,
            "status": t.statusRaw,
            "group": t.group,
        ]
        if let label = t.label { d["label"] = label }
        if let due = t.dueDate {
            let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
            d["due_date"] = f.string(from: due)
        }
        return d
    }

    // MARK: list_tasks

    private struct ListArgs: Decodable {
        let status: String?
        let group: String?
        let dueWithinDays: Int?
        enum CodingKeys: String, CodingKey { case status, group, dueWithinDays = "due_within_days" }
    }

    private static var listTasks: AnyCoachTool {
        .make(
            name: "list_tasks",
            label: "Reviewing your tasks",
            description: "List the user's to-do tasks. Optionally filter by status (todo/in_progress/done/cancelled), group/project name, and due_within_days (tasks due in the next N days). Returns ids you can pass to update_task, complete_task, or delete_task.",
            parameters: JSONSchema.object([
                "status": ["type": ["string", "null"], "enum": statusEnum + [NSNull()]],
                "group": ["type": ["string", "null"]],
                "due_within_days": ["type": ["integer", "null"]],
            ], required: ["status", "group", "due_within_days"]),
            argsType: ListArgs.self
        ) { args, ctx in
            var tasks = fetchAll(ctx)
            if let status = args.status, !status.isEmpty {
                tasks = tasks.filter { $0.statusRaw == status }
            }
            if let group = args.group, !group.isEmpty {
                tasks = tasks.filter { $0.group.caseInsensitiveCompare(group) == .orderedSame }
            }
            if let days = args.dueWithinDays {
                let cutoff = Calendar.current.date(byAdding: .day, value: max(0, days), to: Date()) ?? Date()
                tasks = tasks.filter { ($0.dueDate.map { $0 <= cutoff }) ?? false }
            }
            let sorted = tasks.sorted {
                ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
            }
            return .object(["tasks": sorted.prefix(50).map(dict), "count": sorted.count])
        }
    }

    // MARK: get_task

    private struct IdArgs: Decodable { let taskId: String; enum CodingKeys: String, CodingKey { case taskId = "task_id" } }

    private static var getTask: AnyCoachTool {
        .make(
            name: "get_task",
            label: "Reading a task",
            description: "Get one task by id (from list_tasks).",
            parameters: JSONSchema.object(["task_id": JSONSchema.string], required: ["task_id"]),
            argsType: IdArgs.self
        ) { args, ctx in
            guard let id = UUID(uuidString: args.taskId),
                  let t = fetchAll(ctx).first(where: { $0.id == id }) else {
                return .error("task '\(args.taskId)' not found. Call list_tasks for valid ids.")
            }
            return .object(dict(t))
        }
    }

    // MARK: update_task

    private struct UpdateArgs: Decodable {
        let taskId: String
        let title: String?
        let group: String?
        let status: String?
        let dueDate: String?
        enum CodingKeys: String, CodingKey {
            case taskId = "task_id", title, group, status, dueDate = "due_date"
        }
    }

    private static var updateTask: AnyCoachTool {
        .make(
            name: "update_task",
            label: "Updating a task",
            description: "Update a task's title, group, status, or due date (ISO yyyy-MM-dd). Pass only fields to change; leave others null. Applies immediately. To just mark done, prefer complete_task.",
            parameters: JSONSchema.object([
                "task_id": JSONSchema.string,
                "title": ["type": ["string", "null"]],
                "group": ["type": ["string", "null"]],
                "status": ["type": ["string", "null"], "enum": statusEnum + [NSNull()]],
                "due_date": ["type": ["string", "null"]],
            ], required: ["task_id", "title", "group", "status", "due_date"]),
            argsType: UpdateArgs.self
        ) { args, ctx in
            guard let id = UUID(uuidString: args.taskId),
                  let t = fetchAll(ctx).first(where: { $0.id == id }) else {
                return .error("task '\(args.taskId)' not found.")
            }
            var changed: [String] = []
            if let title = args.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                t.title = title; changed.append("title")
            }
            if let group = args.group, !group.isEmpty { t.group = group; changed.append("group") }
            if let status = args.status, statusEnum.contains(status) { t.statusRaw = status; changed.append("status") }
            if let due = args.dueDate {
                t.dueDate = due.isEmpty ? nil : CoachDataAccess.parseLocalDate(due)
                changed.append("due_date")
            }
            guard !changed.isEmpty else { return .error("no valid fields to update.") }
            t.updatedAt = Date()
            ctx.modelContext.saveOrLog("coach.task")
            return .object(["ok": true, "updated": changed, "task_id": t.id.uuidString, "title": t.title])
        }
    }

    // MARK: complete_task

    private struct CompleteArgs: Decodable {
        let taskId: String
        let done: Bool
        enum CodingKeys: String, CodingKey { case taskId = "task_id", done }
    }

    private static var completeTask: AnyCoachTool {
        .make(
            name: "complete_task",
            label: "Checking off a task",
            description: "Mark a task done (done=true) or reopen it to todo (done=false). Applies immediately.",
            parameters: JSONSchema.object([
                "task_id": JSONSchema.string,
                "done": JSONSchema.boolean,
            ], required: ["task_id", "done"]),
            argsType: CompleteArgs.self
        ) { args, ctx in
            guard let id = UUID(uuidString: args.taskId),
                  let t = fetchAll(ctx).first(where: { $0.id == id }) else {
                return .error("task '\(args.taskId)' not found.")
            }
            t.status = args.done ? .done : .todo
            t.updatedAt = Date()
            ctx.modelContext.saveOrLog("coach.task")
            return .object(["ok": true, "task_id": t.id.uuidString, "status": t.statusRaw, "title": t.title])
        }
    }

    // MARK: delete_task

    private static var deleteTask: AnyCoachTool {
        .make(
            name: "delete_task",
            label: "Removing a task",
            description: "Permanently delete a task by id. Always returns needs_confirmation and shows a Confirm card; deletion only happens after the user taps Confirm. Set response_type to action_confirmation.",
            parameters: JSONSchema.object(["task_id": JSONSchema.string], required: ["task_id"]),
            argsType: IdArgs.self
        ) { args, ctx in
            guard let id = UUID(uuidString: args.taskId),
                  let t = fetchAll(ctx).first(where: { $0.id == id }) else {
                return .error("task '\(args.taskId)' not found.")
            }
            ctx.pendingActions.append(PendingAction(
                kind: .deleteEntity,
                summary: "Delete the task \"\(t.title)\"? This can't be undone.",
                confirmLabel: "Delete",
                entity: EntityActionPayload(entityType: "task", id: t.id.uuidString, displayName: t.title)
            ))
            return .object(["ok": true, "needs_confirmation": true,
                            "summary": "Awaiting your confirmation to delete \"\(t.title)\"."])
        }
    }
}
