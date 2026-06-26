import Foundation
import SwiftData

// MARK: - Spec Sub-App Entity Coach Tools (Phase F1)
//
// Generic CRUD over the records of *any* spec-driven sub-app (built-in specs and
// user-created/installed ones). Spec sub-apps store rows in the single
// `DynamicSubAppRecord` table keyed by sub-app id + entity name; these tools let
// the brain discover a sub-app's entities/fields and read/write its records so a
// user-built mini-app is as controllable as the built-in modules.
//
// Reads always on; writes gated by `flags.writeToolsEnabled`. Create/update apply
// immediately; delete routes through a `.deleteEntity` confirm card.
@MainActor
enum SpecEntityTools {
    static var readTools: [AnyCoachTool] { [listSpecEntities, listSpecRecords] }
    static var writeTools: [AnyCoachTool] { [createSpecRecord, updateSpecRecord, deleteSpecRecord] }

    private static func spec(_ id: String) -> SubAppSpec? {
        SpecSubAppCatalog.shared.spec(for: id)
    }
    private static func store(_ ctx: ToolExecutionContext) -> SwiftDataSubAppRecordStore {
        SwiftDataSubAppRecordStore(context: ctx.modelContext)
    }

    private static func entitySpec(subAppID: String, entity: String) -> EntitySpec? {
        spec(subAppID)?.entities.first { $0.name == entity }
    }

    // MARK: list_spec_entities

    private struct SubAppArgs: Decodable {
        let subAppId: String
        enum CodingKeys: String, CodingKey { case subAppId = "subapp_id" }
    }

    private static var listSpecEntities: AnyCoachTool {
        .make(
            name: "list_spec_entities",
            label: "Inspecting a custom app",
            description: "For a spec-driven (user-built/installed) sub-app, list its data entities and each entity's fields (name, label, type, required, options). Use the module id from list_modules. Call before reading/writing records so you use correct entity + field names.",
            parameters: JSONSchema.object(["subapp_id": JSONSchema.string], required: ["subapp_id"]),
            argsType: SubAppArgs.self
        ) { args, _ in
            guard let s = spec(args.subAppId) else {
                return .error("no spec sub-app with id '\(args.subAppId)'. (Built-in Swift modules aren't spec-driven.)")
            }
            let entities = s.entities.map { e -> [String: Any] in
                [
                    "name": e.name,
                    "label": e.label,
                    "fields": e.fields.map { f -> [String: Any] in
                        var d: [String: Any] = ["name": f.name, "label": f.label,
                                                "type": f.type.rawValue, "required": f.required]
                        if !f.options.isEmpty { d["options"] = f.options }
                        return d
                    },
                ]
            }
            return .object(["subapp_id": s.id, "name": s.displayName, "entities": entities])
        }
    }

    // MARK: list_spec_records

    private struct EntityArgs: Decodable {
        let subAppId: String
        let entity: String
        enum CodingKeys: String, CodingKey { case subAppId = "subapp_id", entity }
    }

    private static var listSpecRecords: AnyCoachTool {
        .make(
            name: "list_spec_records",
            label: "Reading custom-app data",
            description: "List stored records for one entity of a spec sub-app (ids + field values + created date). Use list_spec_entities first for valid entity names.",
            parameters: JSONSchema.object([
                "subapp_id": JSONSchema.string,
                "entity": JSONSchema.string,
            ], required: ["subapp_id", "entity"]),
            argsType: EntityArgs.self
        ) { args, ctx in
            guard entitySpec(subAppID: args.subAppId, entity: args.entity) != nil else {
                return .error("entity '\(args.entity)' not found on '\(args.subAppId)'. Call list_spec_entities.")
            }
            let f = ISO8601DateFormatter()
            let rows = store(ctx).records(subAppID: args.subAppId, entity: args.entity).prefix(50).map { r -> [String: Any] in
                ["id": r.id.uuidString,
                 "created_at": f.string(from: r.createdAt),
                 "values": r.values.mapValues { $0.displayString }]
            }
            return .object(["subapp_id": args.subAppId, "entity": args.entity,
                            "records": Array(rows), "count": rows.count])
        }
    }

    // MARK: create_spec_record / update_spec_record

    private struct WriteArgs: Decodable {
        let subAppId: String
        let entity: String
        let recordId: String?
        /// Field name → value (string/number/bool, coerced to the field's type).
        let values: [String: JSONValue]
        enum CodingKeys: String, CodingKey {
            case subAppId = "subapp_id", entity, recordId = "record_id", values
        }
    }

    private static func coerce(_ value: JSONValue, to type: FieldType, options: [String]) -> SubAppFieldValue? {
        switch type {
        case .text:
            return .text(value.stringValue)
        case .number:
            return value.doubleValue.map { .number($0) }
        case .integer, .rating:
            guard let i = value.intValue else { return nil }
            return type == .rating ? .integer(min(5, max(1, i))) : .integer(i)
        case .boolean:
            return .boolean(value.boolValue ?? false)
        case .date:
            if let d = CoachDataAccess.parseLocalDate(value.stringValue) { return .date(d) }
            return .date(Date())
        case .selection:
            let s = value.stringValue
            return options.isEmpty || options.contains(s) ? .selection(s) : nil
        }
    }

    private static func applyWrite(_ args: WriteArgs, ctx: ToolExecutionContext, isUpdate: Bool) -> ToolResult {
        guard let espec = entitySpec(subAppID: args.subAppId, entity: args.entity) else {
            return .error("entity '\(args.entity)' not found on '\(args.subAppId)'. Call list_spec_entities.")
        }
        let fieldsByName = Dictionary(uniqueKeysWithValues: espec.fields.map { ($0.name, $0) })

        var existing: [String: SubAppFieldValue] = [:]
        var recordUUID = UUID()
        if isUpdate {
            guard let rid = args.recordId, let uuid = UUID(uuidString: rid) else {
                return .error("update requires a valid record_id.")
            }
            guard let row = store(ctx).records(subAppID: args.subAppId, entity: args.entity)
                .first(where: { $0.id == uuid }) else {
                return .error("record '\(rid)' not found. Call list_spec_records.")
            }
            existing = row.values
            recordUUID = uuid
        }

        var rejected: [String] = []
        for (key, raw) in args.values {
            guard let field = fieldsByName[key] else { rejected.append(key); continue }
            guard let coerced = coerce(raw, to: field.type, options: field.options) else {
                rejected.append(key); continue
            }
            existing[key] = coerced
        }

        if !isUpdate {
            for field in espec.fields where field.required && existing[field.name] == nil {
                return .error("missing required field '\(field.name)' (\(field.label)).")
            }
        }
        guard !existing.isEmpty else { return .error("no valid field values provided. Rejected: \(rejected).") }

        let record = SubAppRecord(id: recordUUID, values: existing)
        store(ctx).upsert(record, subAppID: args.subAppId, entity: args.entity)
        var out: [String: Any] = ["ok": true, "record_id": recordUUID.uuidString,
                                  "subapp_id": args.subAppId, "entity": args.entity,
                                  isUpdate ? "updated" : "created": true]
        if !rejected.isEmpty { out["ignored_fields"] = rejected }
        return .object(out)
    }

    private static var createSpecRecord: AnyCoachTool {
        .make(
            name: "create_spec_record",
            label: "Adding custom-app data",
            description: "Create a record in a spec sub-app entity. `values` maps field name → value (text/number/bool; dates as yyyy-MM-dd). Required fields must be present. Applies immediately. Use list_spec_entities for field names/types.",
            parameters: JSONSchema.object([
                "subapp_id": JSONSchema.string,
                "entity": JSONSchema.string,
                "record_id": ["type": ["string", "null"]],
                "values": ["type": "object", "additionalProperties": true],
            ], required: ["subapp_id", "entity", "record_id", "values"]),
            argsType: WriteArgs.self
        ) { args, ctx in applyWrite(args, ctx: ctx, isUpdate: false) }
    }

    private static var updateSpecRecord: AnyCoachTool {
        .make(
            name: "update_spec_record",
            label: "Updating custom-app data",
            description: "Update an existing record (pass record_id from list_spec_records). `values` maps the field names to change → new values; other fields are preserved. Applies immediately.",
            parameters: JSONSchema.object([
                "subapp_id": JSONSchema.string,
                "entity": JSONSchema.string,
                "record_id": JSONSchema.string,
                "values": ["type": "object", "additionalProperties": true],
            ], required: ["subapp_id", "entity", "record_id", "values"]),
            argsType: WriteArgs.self
        ) { args, ctx in applyWrite(args, ctx: ctx, isUpdate: true) }
    }

    // MARK: delete_spec_record

    private struct DeleteArgs: Decodable {
        let subAppId: String
        let entity: String
        let recordId: String
        enum CodingKeys: String, CodingKey { case subAppId = "subapp_id", entity, recordId = "record_id" }
    }

    private static var deleteSpecRecord: AnyCoachTool {
        .make(
            name: "delete_spec_record",
            label: "Removing custom-app data",
            description: "Permanently delete a record from a spec sub-app entity. Always returns needs_confirmation and shows a Confirm card; deletion only happens after the user taps Confirm. Set response_type to action_confirmation.",
            parameters: JSONSchema.object([
                "subapp_id": JSONSchema.string,
                "entity": JSONSchema.string,
                "record_id": JSONSchema.string,
            ], required: ["subapp_id", "entity", "record_id"]),
            argsType: DeleteArgs.self
        ) { args, ctx in
            guard entitySpec(subAppID: args.subAppId, entity: args.entity) != nil else {
                return .error("entity '\(args.entity)' not found on '\(args.subAppId)'.")
            }
            guard let uuid = UUID(uuidString: args.recordId),
                  store(ctx).records(subAppID: args.subAppId, entity: args.entity).contains(where: { $0.id == uuid }) else {
                return .error("record '\(args.recordId)' not found. Call list_spec_records.")
            }
            let label = spec(args.subAppId)?.displayName ?? args.subAppId
            ctx.pendingActions.append(PendingAction(
                kind: .deleteEntity,
                summary: "Delete this \(args.entity) record from \(label)? This can't be undone.",
                confirmLabel: "Delete",
                entity: EntityActionPayload(entityType: "spec_record:\(args.subAppId):\(args.entity)",
                                            id: args.recordId, displayName: "\(args.entity) record")
            ))
            return .object(["ok": true, "needs_confirmation": true,
                            "summary": "Awaiting your confirmation to delete this \(args.entity) record."])
        }
    }
}

// MARK: - Minimal JSON value for free-form tool args

/// Decodes an arbitrary JSON scalar so spec record `values` can carry mixed types
/// without a fixed schema. Only scalars are needed for field values.
enum JSONValue: Decodable {
    case string(String)
    case double(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let d = try? c.decode(Double.self) { self = .double(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else { self = .null }
    }

    var stringValue: String {
        switch self {
        case let .string(s): return s
        case let .double(d): return d == d.rounded() ? String(Int(d)) : String(d)
        case let .bool(b): return b ? "true" : "false"
        case .null: return ""
        }
    }
    var doubleValue: Double? {
        switch self {
        case let .double(d): return d
        case let .string(s): return Double(s)
        default: return nil
        }
    }
    var intValue: Int? { doubleValue.map { Int($0) } ?? Int(stringValue) }
    var boolValue: Bool? {
        switch self {
        case let .bool(b): return b
        case let .string(s): return ["true", "yes", "1"].contains(s.lowercased())
        default: return nil
        }
    }
}
