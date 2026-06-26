import Foundation
import SwiftData

/// Performs a `PendingAction`'s real mutation  -  only ever called after the user
/// taps Confirm on the action card. Returns a short human result string.
@MainActor
enum PendingActionExecutor {
    static func execute(_ action: PendingAction, context: ModelContext) -> String {
        switch action.kind {
        case .disableModule:
            guard let payload = action.platform else { return "That module no longer exists." }
            SubAppRegistry.shared.uninstall(SubAppID(payload.targetId))
            return "Uninstalled \(payload.displayName). Its data is preserved if you reinstall."

        case .removeModuleData:
            guard let payload = action.platform else { return "That module no longer exists." }
            let id = SubAppID(payload.targetId)
            SubAppRegistry.shared.uninstall(id)
            // Spec sub-apps store data in the shared DynamicSubAppRecord table; wipe it.
            // Built-in modules keep their own SwiftData models, which we don't bulk-
            // delete here (uninstall already removed them from the app).
            let store = SwiftDataSubAppRecordStore(context: context)
            let removed = store.deleteAll(subAppID: payload.targetId)
            if removed > 0 {
                return "Uninstalled \(payload.displayName) and removed \(removed) record\(removed == 1 ? "" : "s")."
            }
            return "Uninstalled \(payload.displayName) and cleared its data."

        case .uninstallSubApp:
            guard let payload = action.platform else { return "That sub-app no longer exists." }
            UserSubAppStore.shared.delete(id: payload.targetId)
            SubAppRegistry.shared.loadUserSpecs()
            return "Uninstalled \(payload.displayName)."

        case .installSubApp:
            guard let payload = action.platform else { return "That sub-app draft is no longer available." }
            // The draft is still staged in the builder draft store; commit it now.
            guard let draft = SubAppBuilderDraftStore.shared.draft, draft.id == payload.targetId else {
                return "That sub-app draft is no longer available. Describe it again to rebuild it."
            }
            // Final gate before committing (the draft can't change between staging
            // and confirm, but validate defensively so we never install a bad spec).
            let errors = SubAppSpecValidator.issues(in: draft).filter { $0.severity == .error }
            guard errors.isEmpty, SubAppGuardrails.review(draft).canSave else {
                return "Couldn't install \(payload.displayName): the design has a validation problem. Try refining it."
            }
            UserSubAppStore.shared.save(draft)
            SubAppRegistry.shared.loadUserSpecs()
            SubAppRegistry.shared.install(SubAppID(draft.id))
            SubAppBuilderDraftStore.shared.clear()
            // Open the freshly installed module so the user lands right in it.
            CoachNavigation.shared.requestNavigation(route: .subApp(draft.id))
            return "Installed \(draft.displayName). Opening it now."

        case .updateModule:
            guard let payload = action.platform else { return "That module no longer exists." }
            let id = SubAppID(payload.targetId)
            guard let newVersion = SubAppRegistry.shared.applyUpdate(id, context: context) else {
                return "\(payload.displayName) is already up to date."
            }
            return "Updated \(payload.displayName) to v\(newVersion)."

        case .applyModuleImprovement:
            guard let payload = action.platform else { return "That improvement is no longer available." }
            guard let proposal = ModuleImprovementStore.shared.proposal(for: payload.targetId) else {
                return "That improvement is no longer available."
            }
            if let reason = ModuleImprovementApplier.validationFailure(proposal.proposedSpec) {
                return "Couldn't apply the improvement to \(payload.displayName): \(reason)"
            }
            let newVersion = ModuleImprovementApplier.commit(proposal, context: context)
            return "Improved \(payload.displayName) to v\(newVersion)."

        case .deleteActivitySession, .updateActivitySession:
            return executeActivity(action, context: context)

        case .deleteEntity:
            return executeEntityDelete(action, context: context)
        }
    }

    /// Generic delete-by-type for tasks, notes, medications, and other
    /// brain-managed entities. Cascade relationships handle children where the
    /// model declares them (e.g. `Note.blocks`).
    private static func executeEntityDelete(_ action: PendingAction, context: ModelContext) -> String {
        guard let payload = action.entity, let uuid = UUID(uuidString: payload.id) else {
            return "That item no longer exists."
        }
        let name = payload.displayName
        switch payload.entityType {
        case "task":
            guard let item = try? context.fetch(FetchDescriptor<TaskItem>()).first(where: { $0.id == uuid }) else {
                return "That task no longer exists."
            }
            context.delete(item)
            context.saveOrLog("pendingAction")
            return "Deleted the task \"\(name)\"."

        case "note":
            guard let note = try? context.fetch(FetchDescriptor<Note>()).first(where: { $0.id == uuid }) else {
                return "That note no longer exists."
            }
            context.delete(note)
            context.saveOrLog("pendingAction")
            return "Deleted the note \"\(name)\"."

        case "medication":
            guard let med = try? context.fetch(FetchDescriptor<Medication>()).first(where: { $0.id == uuid }) else {
                return "That medication no longer exists."
            }
            context.delete(med)
            context.saveOrLog("pendingAction")
            return "Deleted \(name)."

        case "trip_item":
            guard let item = try? context.fetch(FetchDescriptor<TripItem>()).first(where: { $0.id == uuid }) else {
                return "That trip item no longer exists."
            }
            context.delete(item)
            context.saveOrLog("pendingAction")
            return "Removed \"\(name)\" from the trip."

        case "trip":
            guard let trip = try? context.fetch(FetchDescriptor<Trip>()).first(where: { $0.id == uuid }) else {
                return "That trip no longer exists."
            }
            trip.status = .cancelled
            trip.updatedAt = Date()
            context.saveOrLog("pendingAction")
            return "Archived your trip to \(name)."

        default:
            // Spec sub-app record: entityType is "spec_record:<subAppID>:<entity>".
            if payload.entityType.hasPrefix("spec_record:") {
                let parts = payload.entityType.split(separator: ":", maxSplits: 2).map(String.init)
                guard parts.count == 3 else { return "Unknown item; nothing was deleted." }
                let store = SwiftDataSubAppRecordStore(context: context)
                store.delete(uuid, subAppID: parts[1], entity: parts[2])
                return "Deleted the \(parts[2]) record."
            }
            return "Unknown item type; nothing was deleted."
        }
    }

    private static func executeActivity(_ action: PendingAction, context: ModelContext) -> String {
        guard let id = UUID(uuidString: action.activityId),
              let session = ActivityRepository.sessions(context: context).first(where: { $0.id == id }) else {
            return "That workout no longer exists."
        }
        let typeLabel = ActivityMeta.label(session.type)

        switch action.kind {
        case .deleteActivitySession:
            for sample in ActivityRepository.samples(sessionId: id, context: context) { context.delete(sample) }
            for point in ActivityRepository.gpsPoints(sessionId: id, context: context) { context.delete(point) }
            for event in ActivityRepository.events(sessionId: id, context: context) { context.delete(event) }
            context.delete(session)
            context.saveOrLog("pendingAction")
            return "Deleted the \(typeLabel) session."

        case .updateActivitySession:
            apply(action.updates, to: session)
            session.updatedAt = Date()
            context.saveOrLog("pendingAction")
            return "Updated the \(typeLabel) session."

        default:
            return "Nothing to do."
        }
    }

    private static func apply(_ updates: ActivityUpdates?, to session: ActivitySession) {
        guard let updates else { return }
        if let type = updates.type { session.type = type }
        if let notes = updates.notes { session.notes = notes }
        if let distanceKm = updates.distanceKm { session.distanceMeters = distanceKm * 1000 }
        if let effort = updates.perceivedEffort { session.perceivedEffort = effort }
        if let start = updates.startTime, let date = CoachDataAccess.parseLocalDate(start) {
            session.startedAt = date
        }
        if let durationMin = updates.durationMin {
            session.endedAt = session.startedAt.addingTimeInterval(durationMin * 60 + session.totalPauseSeconds)
        }
    }
}
