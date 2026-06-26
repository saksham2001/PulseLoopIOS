import Foundation
import SwiftData

// MARK: - Spec-driven persistence (roadmap C3)
//
// SwiftData needs a fixed @Model schema at container-build time, so dynamic
// spec-defined entities can't each become their own table at runtime. Instead the
// platform stores every dynamic record in ONE generic table, `DynamicSubAppRecord`,
// keyed by sub-app id + entity name, with the field values serialized to a JSON
// blob. This is additive: adding the single model to the schema never disturbs the
// existing per-feature models, and new sub-apps/entities add zero new tables.

@Model
final class DynamicSubAppRecord {
    @Attribute(.unique) var id: UUID
    /// Owning sub-app id (`SubAppSpec.id`).
    var subAppID: String
    /// Entity name within that sub-app (`EntitySpec.name`). Named `entityName` (not
    /// `entity`) because `entity` collides with CoreData's reserved `NSManagedObject.entity`
    /// and aborts entity-description construction.
    var entityName: String
    var createdAt: Date
    var updatedAt: Date
    /// JSON-encoded `[String: CodableFieldValue]` payload of the record's fields,
    /// stored as a UTF-8 string. (A `String` attribute avoids SwiftData abort paths
    /// some toolchains hit when fetching/saving raw `Data` columns.)
    var payloadJSON: String

    init(id: UUID = UUID(), subAppID: String, entityName: String, payloadJSON: String) {
        self.id = id
        self.subAppID = subAppID
        self.entityName = entityName
        self.createdAt = Date()
        self.updatedAt = Date()
        self.payloadJSON = payloadJSON
    }
}

// MARK: - Codable bridge for field values

/// JSON-friendly mirror of `SubAppFieldValue` used only for persistence.
enum CodableFieldValue: Codable {
    case text(String)
    case number(Double)
    case integer(Int)
    case boolean(Bool)
    case date(Date)
    case selection(String)
    case empty

    init(_ value: SubAppFieldValue) {
        switch value {
        case let .text(s): self = .text(s)
        case let .number(n): self = .number(n)
        case let .integer(i): self = .integer(i)
        case let .boolean(b): self = .boolean(b)
        case let .date(d): self = .date(d)
        case let .selection(s): self = .selection(s)
        case .empty: self = .empty
        }
    }

    var runtimeValue: SubAppFieldValue {
        switch self {
        case let .text(s): return .text(s)
        case let .number(n): return .number(n)
        case let .integer(i): return .integer(i)
        case let .boolean(b): return .boolean(b)
        case let .date(d): return .date(d)
        case let .selection(s): return .selection(s)
        case .empty: return .empty
        }
    }
}

// MARK: - SwiftData-backed record store

/// Production `SubAppRecordStore` backed by `DynamicSubAppRecord` in SwiftData.
/// Drop-in replacement for `InMemorySubAppRecordStore` — same protocol surface.
@MainActor
final class SwiftDataSubAppRecordStore: SubAppRecordStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func records(subAppID: String, entity: String) -> [SubAppRecord] {
        // String captures in #Predicate are usually fine, but keep all dynamic-record
        // access on the same in-memory-filter path for consistency and to dodge
        // SwiftData predicate-translation aborts.
        let descriptor = FetchDescriptor<DynamicSubAppRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let rows = ((try? context.fetch(descriptor)) ?? [])
            .filter { $0.subAppID == subAppID && $0.entityName == entity }
        return rows.map { row in
            let decoded = (try? JSONDecoder().decode([String: CodableFieldValue].self,
                                                     from: Data(row.payloadJSON.utf8))) ?? [:]
            return SubAppRecord(
                id: row.id,
                values: decoded.mapValues { $0.runtimeValue },
                createdAt: row.createdAt
            )
        }
    }

    func upsert(_ record: SubAppRecord, subAppID: String, entity: String) {
        let payload = encode(record.values)
        let recordID = record.id
        // Filter in-memory rather than via a UUID #Predicate: comparing a UUID
        // attribute to a captured UUID in #Predicate aborts on some SwiftData builds.
        let all = (try? context.fetch(FetchDescriptor<DynamicSubAppRecord>())) ?? []
        if let existing = all.first(where: { $0.id == recordID }) {
            existing.payloadJSON = payload
            existing.updatedAt = Date()
        } else {
            context.insert(DynamicSubAppRecord(id: record.id, subAppID: subAppID, entityName: entity, payloadJSON: payload))
        }
        context.saveOrLog("subapp.upsert")
    }

    func delete(_ id: UUID, subAppID: String, entity: String) {
        let all = (try? context.fetch(FetchDescriptor<DynamicSubAppRecord>())) ?? []
        if let row = all.first(where: { $0.id == id }) {
            context.delete(row)
            context.saveOrLog("subapp.delete")
        }
    }

    /// Delete every record belonging to a spec sub-app (all entities). Used by the
    /// confirmed "uninstall and remove data" path. Returns the count removed.
    @discardableResult
    func deleteAll(subAppID: String) -> Int {
        let all = (try? context.fetch(FetchDescriptor<DynamicSubAppRecord>())) ?? []
        let toRemove = all.filter { $0.subAppID == subAppID }
        for row in toRemove { context.delete(row) }
        if !toRemove.isEmpty { context.saveOrLog("subapp.deleteAll") }
        return toRemove.count
    }

    private func encode(_ values: [String: SubAppFieldValue]) -> String {
        let codable = values.mapValues { CodableFieldValue($0) }
        let data = (try? JSONEncoder().encode(codable)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
