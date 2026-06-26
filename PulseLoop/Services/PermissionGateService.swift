import Foundation
import SwiftData

/// Gates all AI write-actions through permission checks and logs to the audit trail.
/// Every action is recorded and reversible.
@MainActor
final class PermissionGateService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    enum Permission: String {
        case allowed, ask, denied
    }

    /// Checks whether a given action type is permitted.
    func check(action: String) -> Permission {
        let descriptor = FetchDescriptor<PermissionGate>(predicate: #Predicate { $0.actionType == action })
        guard let gate = try? context.fetch(descriptor).first else {
            return .ask
        }
        return Permission(rawValue: gate.permissionLevel) ?? .ask
    }

    /// Records an action to the append-only audit log.
    func logAction(_ description: String, source: String? = nil, reversible: Bool = true) {
        let entry = AuditLogEntry(
            actionDescription: description,
            sourceContext: source,
            isReversible: reversible
        )
        context.insert(entry)
        context.saveOrLog("permissionGate")
    }

    /// Undoes an action by marking it in the audit log.
    func undo(entryId: UUID) {
        let descriptor = FetchDescriptor<AuditLogEntry>(predicate: #Predicate { $0.id == entryId })
        guard let entry = try? context.fetch(descriptor).first else { return }
        guard entry.isReversible else { return }
        entry.wasUndone = true
        context.saveOrLog("permissionGate")
    }

    /// Returns recent audit log entries.
    func recentLog(limit: Int = 20) -> [AuditLogEntry] {
        var descriptor = FetchDescriptor<AuditLogEntry>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }
}
