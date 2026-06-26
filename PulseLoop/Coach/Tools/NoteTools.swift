import Foundation
import SwiftData

// MARK: - Note Coach Tools (AI-first Notes)
//
// Full read/edit surface over `Note` + `NoteBlock` so the brain can capture,
// recall, restructure, tag, and link notes conversationally. Reads always on;
// writes gated by `flags.writeToolsEnabled`. Creating/appending/editing/tagging
// applies immediately; deleting a note routes through a `.deleteEntity` confirm.
//
// `create_note` lives in `PlatformControlTools`; these tools complete the surface.
@MainActor
enum NoteTools {
    static var readTools: [AnyCoachTool] { [listNotes, readNote, listCollections] }
    static var writeTools: [AnyCoachTool] {
        [captureAndFile, appendToNote, editNoteBlock, setNoteTags, summarizeNote,
         setNoteCollection, linkNotes, linkNoteToTask, deleteNote]
    }

    private static let blockKindEnum = ["heading", "paragraph", "todo", "quote",
                                        "aiInsight", "bulletList", "numberedList", "divider", "callout"]

    private static func notes(_ ctx: ToolExecutionContext) -> [Note] {
        (try? ctx.modelContext.fetch(FetchDescriptor<Note>())) ?? []
    }

    private static func plainText(_ note: Note) -> String {
        note.blocks.sorted { $0.order < $1.order }.map(\.content).joined(separator: "\n")
    }

    // MARK: capture_and_file

    private struct CaptureArgs: Decodable { let text: String }

    private static var captureAndFile: AnyCoachTool {
        .make(
            name: "capture_and_file",
            label: "Capturing and filing",
            description: "Turn a raw, rambling brain-dump (typed or dictated) into a clean, organized note PLUS extracted to-do tasks, filed across the app. Use this when the user pastes/says a stream of thoughts, asks to 'capture this', 'plan my week', or 'sort out my notes'. Returns the new note id (open it with navigate_to notes or read_note). Applies immediately.",
            parameters: JSONSchema.object(["text": JSONSchema.string], required: ["text"]),
            argsType: CaptureArgs.self
        ) { args, ctx in
            let text = args.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return .error("text is empty.") }
            let router = VoiceCaptureRouter()
            let plan = await router.plan(from: text)
            let applied = router.apply(plan, in: ctx.modelContext, summaryPrefix: "Captured")
            return .object([
                "ok": true,
                "note_id": applied.note.id.uuidString,
                "title": applied.note.title,
                "task_count": applied.taskCount,
                "scheduled_count": applied.scheduledCount,
                "note": "Filed a structured note plus \(applied.taskCount) task(s). Offer to open it.",
            ])
        }
    }

    // MARK: list_notes

    private struct ListArgs: Decodable {
        let query: String?
        let tag: String?
        let limit: Int?
    }

    private static var listNotes: AnyCoachTool {
        .make(
            name: "list_notes",
            label: "Searching your notes",
            description: "List/search the user's notes. Optional `query` matches against title AND body text (case-insensitive). Optional `tag` filters by a note tag. Returns ids, titles, tags, a short preview, and updated date — pass an id to read_note for the full content.",
            parameters: JSONSchema.object([
                "query": ["type": ["string", "null"]],
                "tag": ["type": ["string", "null"]],
                "limit": ["type": ["integer", "null"]],
            ], required: ["query", "tag", "limit"]),
            argsType: ListArgs.self
        ) { args, ctx in
            var items = notes(ctx)
            if let q = args.query?.trimmingCharacters(in: .whitespaces), !q.isEmpty {
                let needle = q.lowercased()
                items = items.filter {
                    $0.title.lowercased().contains(needle) || plainText($0).lowercased().contains(needle)
                }
            }
            if let tag = args.tag, !tag.isEmpty {
                items = items.filter { $0.tags.contains { $0.caseInsensitiveCompare(tag) == .orderedSame } }
            }
            let f = ISO8601DateFormatter(); f.formatOptions = [.withFullDate]
            let sorted = items.sorted { $0.updatedAt > $1.updatedAt }.prefix(args.limit.map { max(1, $0) } ?? 25)
            let rows = sorted.map { n -> [String: Any] in
                let body = plainText(n)
                return [
                    "id": n.id.uuidString,
                    "title": n.title.isEmpty ? "Untitled" : n.title,
                    "tags": n.tags,
                    "preview": String(body.prefix(140)),
                    "updated": f.string(from: n.updatedAt),
                ]
            }
            return .object(["notes": rows, "count": rows.count, "total": items.count])
        }
    }

    // MARK: read_note

    private struct IdArgs: Decodable { let noteId: String; enum CodingKeys: String, CodingKey { case noteId = "note_id" } }

    private static var readNote: AnyCoachTool {
        .make(
            name: "read_note",
            label: "Reading a note",
            description: "Get a note's full content by id: title, tags, summary, linked task, and every block (with its id, order, kind, content, checked-state) so you can edit specific blocks via edit_note_block.",
            parameters: JSONSchema.object(["note_id": JSONSchema.string], required: ["note_id"]),
            argsType: IdArgs.self
        ) { args, ctx in
            guard let id = UUID(uuidString: args.noteId), let note = notes(ctx).first(where: { $0.id == id }) else {
                return .error("note '\(args.noteId)' not found. Call list_notes for valid ids.")
            }
            let blocks = note.blocks.sorted { $0.order < $1.order }.map { b in
                ["id": b.id.uuidString, "order": b.order, "kind": b.kindRaw,
                 "content": b.content, "is_checked": b.isChecked] as [String: Any]
            }
            var out: [String: Any] = ["id": note.id.uuidString, "title": note.title,
                                      "tags": note.tags, "blocks": blocks]
            if let s = note.aiSummary { out["summary"] = s }
            if let t = note.linkedTaskId { out["linked_task_id"] = t.uuidString }
            return .object(out)
        }
    }

    // MARK: append_to_note

    private struct AppendArgs: Decodable {
        let noteId: String
        let content: String
        let kind: String?
        enum CodingKeys: String, CodingKey { case noteId = "note_id", content, kind }
    }

    private static var appendToNote: AnyCoachTool {
        .make(
            name: "append_to_note",
            label: "Adding to a note",
            description: "Append content to a note. `content` may contain multiple lines (each becomes a block of the given kind). kind defaults to paragraph; use todo for action items, heading for sections, bulletList for bullets, aiInsight for your own observations. Applies immediately.",
            parameters: JSONSchema.object([
                "note_id": JSONSchema.string,
                "content": JSONSchema.string,
                "kind": ["type": ["string", "null"], "enum": blockKindEnum + [NSNull()]],
            ], required: ["note_id", "content", "kind"]),
            argsType: AppendArgs.self
        ) { args, ctx in
            guard let id = UUID(uuidString: args.noteId), let note = notes(ctx).first(where: { $0.id == id }) else {
                return .error("note '\(args.noteId)' not found.")
            }
            let kind = NoteBlockKind(rawValue: args.kind ?? "paragraph") ?? .paragraph
            var order = (note.blocks.map(\.order).max() ?? -1) + 1
            let lines = args.content.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !lines.isEmpty else { return .error("content is empty.") }
            for line in lines {
                let block = NoteBlock(noteId: note.id, order: order, kind: kind, content: line)
                ctx.modelContext.insert(block)
                note.blocks.append(block)
                order += 1
            }
            note.updatedAt = Date()
            ctx.modelContext.saveOrLog("coach.note")
            return .object(["ok": true, "note_id": note.id.uuidString, "added_blocks": lines.count])
        }
    }

    // MARK: edit_note_block

    private struct EditBlockArgs: Decodable {
        let blockId: String
        let content: String?
        let kind: String?
        let isChecked: Bool?
        let delete: Bool?
        enum CodingKeys: String, CodingKey {
            case blockId = "block_id", content, kind, isChecked = "is_checked", delete
        }
    }

    private static var editNoteBlock: AnyCoachTool {
        .make(
            name: "edit_note_block",
            label: "Editing a note",
            description: "Edit one block of a note (id from read_note): change its content, kind, or checked-state, or delete it (delete=true). Pass only what changes. Applies immediately. Use this for inline conversational edits like 'rewrite the second paragraph' or 'check off that item'.",
            parameters: JSONSchema.object([
                "block_id": JSONSchema.string,
                "content": ["type": ["string", "null"]],
                "kind": ["type": ["string", "null"], "enum": blockKindEnum + [NSNull()]],
                "is_checked": ["type": ["boolean", "null"]],
                "delete": ["type": ["boolean", "null"]],
            ], required: ["block_id", "content", "kind", "is_checked", "delete"]),
            argsType: EditBlockArgs.self
        ) { args, ctx in
            guard let id = UUID(uuidString: args.blockId),
                  let block = ((try? ctx.modelContext.fetch(FetchDescriptor<NoteBlock>())) ?? [])
                    .first(where: { $0.id == id }) else {
                return .error("block '\(args.blockId)' not found. Call read_note for block ids.")
            }
            let note = notes(ctx).first { $0.id == block.noteId }
            if args.delete == true {
                ctx.modelContext.delete(block)
                note?.updatedAt = Date()
                ctx.modelContext.saveOrLog("coach.note")
                return .object(["ok": true, "deleted_block": id.uuidString])
            }
            var changed: [String] = []
            if let c = args.content { block.content = c; changed.append("content") }
            if let k = args.kind, let kind = NoteBlockKind(rawValue: k) { block.kind = kind; changed.append("kind") }
            if let checked = args.isChecked { block.isChecked = checked; changed.append("is_checked") }
            guard !changed.isEmpty else { return .error("nothing to change.") }
            note?.updatedAt = Date()
            ctx.modelContext.saveOrLog("coach.note")
            return .object(["ok": true, "block_id": id.uuidString, "updated": changed])
        }
    }

    // MARK: set_note_tags

    private struct TagArgs: Decodable {
        let noteId: String
        let tags: [String]
        enum CodingKeys: String, CodingKey { case noteId = "note_id", tags }
    }

    private static var setNoteTags: AnyCoachTool {
        .make(
            name: "set_note_tags",
            label: "Tagging a note",
            description: "Replace a note's tags with the provided list (use lowercase, hyphen-or-space separated topics). Helps the user find related notes later. Applies immediately.",
            parameters: JSONSchema.object([
                "note_id": JSONSchema.string,
                "tags": ["type": "array", "items": ["type": "string"]],
            ], required: ["note_id", "tags"]),
            argsType: TagArgs.self
        ) { args, ctx in
            guard let id = UUID(uuidString: args.noteId), let note = notes(ctx).first(where: { $0.id == id }) else {
                return .error("note '\(args.noteId)' not found.")
            }
            let cleaned = Array(Set(args.tags.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty })).sorted()
            note.tags = cleaned
            note.updatedAt = Date()
            ctx.modelContext.saveOrLog("coach.note")
            return .object(["ok": true, "note_id": note.id.uuidString, "tags": cleaned])
        }
    }

    // MARK: link_note_to_task

    private struct LinkArgs: Decodable {
        let noteId: String
        let taskId: String?
        enum CodingKeys: String, CodingKey { case noteId = "note_id", taskId = "task_id" }
    }

    private static var linkNoteToTask: AnyCoachTool {
        .make(
            name: "link_note_to_task",
            label: "Linking a note",
            description: "Link a note to a task (pass task_id) so project notes connect to the to-do, or unlink it (task_id null/empty). Applies immediately.",
            parameters: JSONSchema.object([
                "note_id": JSONSchema.string,
                "task_id": ["type": ["string", "null"]],
            ], required: ["note_id", "task_id"]),
            argsType: LinkArgs.self
        ) { args, ctx in
            guard let id = UUID(uuidString: args.noteId), let note = notes(ctx).first(where: { $0.id == id }) else {
                return .error("note '\(args.noteId)' not found.")
            }
            if let tid = args.taskId, let taskUUID = UUID(uuidString: tid) {
                let exists = ((try? ctx.modelContext.fetch(FetchDescriptor<TaskItem>())) ?? [])
                    .contains { $0.id == taskUUID }
                guard exists else { return .error("task '\(tid)' not found.") }
                note.linkedTaskId = taskUUID
            } else {
                note.linkedTaskId = nil
            }
            note.updatedAt = Date()
            ctx.modelContext.saveOrLog("coach.note")
            return .object(["ok": true, "note_id": note.id.uuidString,
                            "linked_task_id": note.linkedTaskId?.uuidString as Any])
        }
    }

    // MARK: summarize_note

    private static var summarizeNote: AnyCoachTool {
        .make(
            name: "summarize_note",
            label: "Summarizing a note",
            description: "Generate (or refresh) the AI summary for a note by id. Reads the note body, writes a concise summary onto the note, and returns it. Use when the user asks 'summarize this' or to keep the list preview useful. Applies immediately.",
            parameters: JSONSchema.object(["note_id": JSONSchema.string], required: ["note_id"]),
            argsType: IdArgs.self
        ) { args, ctx in
            guard let id = UUID(uuidString: args.noteId), let note = notes(ctx).first(where: { $0.id == id }) else {
                return .error("note '\(args.noteId)' not found. Call list_notes for valid ids.")
            }
            let body = plainText(note)
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .error("note has no content to summarize.")
            }
            guard let summary = await AIService.shared.summarizeNote(content: body) else {
                return .error("could not generate a summary right now.")
            }
            note.aiSummary = summary
            note.updatedAt = Date()
            ctx.modelContext.saveOrLog("coach.note")
            return .object(["ok": true, "note_id": note.id.uuidString, "summary": summary])
        }
    }

    // MARK: list_collections

    private static var listCollections: AnyCoachTool {
        .make(
            name: "list_collections",
            label: "Listing collections",
            description: "List the user's note collections (folders) with their ids, names, emoji, and note count. Use to find a collection id for set_note_collection.",
            parameters: JSONSchema.empty,
            argsType: NoArgs.self
        ) { _, ctx in
            let cols = (try? ctx.modelContext.fetch(FetchDescriptor<Collection>())) ?? []
            let allNotes = notes(ctx)
            let rows = cols.sorted { $0.order < $1.order }.map { c -> [String: Any] in
                let count = allNotes.filter { $0.collectionId == c.id }.count
                return ["id": c.id.uuidString, "name": c.name, "emoji": c.emoji, "note_count": count]
            }
            return .object(["collections": rows, "count": rows.count])
        }
    }

    // MARK: set_note_collection

    private struct SetCollectionArgs: Decodable {
        let noteId: String
        let collectionId: String?
        let collectionName: String?
        enum CodingKeys: String, CodingKey {
            case noteId = "note_id", collectionId = "collection_id", collectionName = "collection_name"
        }
    }

    private static var setNoteCollection: AnyCoachTool {
        .make(
            name: "set_note_collection",
            label: "Filing a note",
            description: "File a note into a collection. Pass collection_id (from list_collections) to use an existing one, OR collection_name to find-or-create a collection by name, OR both null to remove the note from any collection. Applies immediately.",
            parameters: JSONSchema.object([
                "note_id": JSONSchema.string,
                "collection_id": ["type": ["string", "null"]],
                "collection_name": ["type": ["string", "null"]],
            ], required: ["note_id", "collection_id", "collection_name"]),
            argsType: SetCollectionArgs.self
        ) { args, ctx in
            guard let id = UUID(uuidString: args.noteId), let note = notes(ctx).first(where: { $0.id == id }) else {
                return .error("note '\(args.noteId)' not found.")
            }
            let cols = (try? ctx.modelContext.fetch(FetchDescriptor<Collection>())) ?? []
            if let cid = args.collectionId, let cUUID = UUID(uuidString: cid) {
                guard cols.contains(where: { $0.id == cUUID }) else { return .error("collection '\(cid)' not found.") }
                note.collectionId = cUUID
            } else if let name = args.collectionName?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                if let existing = cols.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                    note.collectionId = existing.id
                } else {
                    let newCol = Collection(name: name, emoji: "folder", order: (cols.map(\.order).max() ?? -1) + 1)
                    ctx.modelContext.insert(newCol)
                    note.collectionId = newCol.id
                }
            } else {
                note.collectionId = nil
            }
            note.updatedAt = Date()
            ctx.modelContext.saveOrLog("coach.note")
            return .object(["ok": true, "note_id": note.id.uuidString,
                            "collection_id": note.collectionId?.uuidString as Any])
        }
    }

    // MARK: link_notes

    private struct LinkNotesArgs: Decodable {
        let noteId: String
        let targetNoteId: String
        let unlink: Bool?
        enum CodingKeys: String, CodingKey { case noteId = "note_id", targetNoteId = "target_note_id", unlink }
    }

    private static var linkNotes: AnyCoachTool {
        .make(
            name: "link_notes",
            label: "Linking notes",
            description: "Create (or remove with unlink=true) a link between two notes so related ideas connect and show up as backlinks. Pass both note ids. Applies immediately.",
            parameters: JSONSchema.object([
                "note_id": JSONSchema.string,
                "target_note_id": JSONSchema.string,
                "unlink": ["type": ["boolean", "null"]],
            ], required: ["note_id", "target_note_id", "unlink"]),
            argsType: LinkNotesArgs.self
        ) { args, ctx in
            guard let id = UUID(uuidString: args.noteId), let note = notes(ctx).first(where: { $0.id == id }) else {
                return .error("note '\(args.noteId)' not found.")
            }
            guard let tid = UUID(uuidString: args.targetNoteId), tid != id,
                  notes(ctx).contains(where: { $0.id == tid }) else {
                return .error("target note '\(args.targetNoteId)' not found (or same as note_id).")
            }
            if args.unlink == true {
                note.linkedNoteIds.removeAll { $0 == tid }
            } else if !note.linkedNoteIds.contains(tid) {
                note.linkedNoteIds.append(tid)
            }
            note.updatedAt = Date()
            ctx.modelContext.saveOrLog("coach.note")
            return .object(["ok": true, "note_id": note.id.uuidString,
                            "linked_note_ids": note.linkedNoteIds.map(\.uuidString)])
        }
    }

    // MARK: delete_note

    private static var deleteNote: AnyCoachTool {
        .make(
            name: "delete_note",
            label: "Removing a note",
            description: "Permanently delete a note (and its blocks) by id. Always returns needs_confirmation and shows a Confirm card; deletion only happens after the user taps Confirm. Set response_type to action_confirmation.",
            parameters: JSONSchema.object(["note_id": JSONSchema.string], required: ["note_id"]),
            argsType: IdArgs.self
        ) { args, ctx in
            guard let id = UUID(uuidString: args.noteId), let note = notes(ctx).first(where: { $0.id == id }) else {
                return .error("note '\(args.noteId)' not found.")
            }
            let title = note.title.isEmpty ? "Untitled note" : note.title
            ctx.pendingActions.append(PendingAction(
                kind: .deleteEntity,
                summary: "Delete the note \"\(title)\"? This can't be undone.",
                confirmLabel: "Delete",
                entity: EntityActionPayload(entityType: "note", id: note.id.uuidString, displayName: title)
            ))
            return .object(["ok": true, "needs_confirmation": true,
                            "summary": "Awaiting your confirmation to delete \"\(title)\"."])
        }
    }
}
