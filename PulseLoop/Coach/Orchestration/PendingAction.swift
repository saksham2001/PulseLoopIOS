import Foundation

/// A risky write the coach proposed but has NOT performed  -  surfaced to the user
/// as a Confirm/Cancel card and only executed on tap. Persisted as JSON on the
/// assistant `CoachMessage.pendingActionJSON`.
struct PendingAction: Codable, Equatable {
    enum Kind: String, Codable {
        case deleteActivitySession
        case updateActivitySession
        /// Disable a module/sub-app (reversible, but hides a feature → confirmed).
        case disableModule
        /// Uninstall a module AND permanently delete its stored data (spec sub-apps).
        case removeModuleData
        /// Permanently delete a user-created sub-app and its data.
        case uninstallSubApp
        /// Install the AI-designed sub-app draft (staged in `SubAppBuilderDraftStore`)
        /// after the user reviews a live preview and confirms. Reversible.
        case installSubApp
        /// Apply a pending version update to an installed module (runs its migrate hook).
        case updateModule
        /// Apply a self-improvement proposal (staged in `ModuleImprovementStore`) to an
        /// installed declarative module after the user reviews the change.
        case applyModuleImprovement
        /// Generic delete of a SwiftData entity by type + id (tasks, notes,
        /// medications, etc.). Target carried in `entity`.
        case deleteEntity
    }

    var kind: Kind
    var activityId: String
    var summary: String          // human-readable description for the card
    var confirmLabel: String
    var updates: ActivityUpdates?   // only for `updateActivitySession`
    /// Generic payload for platform actions (module/sub-app id, display name, …).
    var platform: PlatformActionPayload?
    /// Generic payload for `deleteEntity` (entity type + UUID string).
    var entity: EntityActionPayload?

    init(
        kind: Kind,
        activityId: String = "",
        summary: String,
        confirmLabel: String,
        updates: ActivityUpdates? = nil,
        platform: PlatformActionPayload? = nil,
        entity: EntityActionPayload? = nil
    ) {
        self.kind = kind
        self.activityId = activityId
        self.summary = summary
        self.confirmLabel = confirmLabel
        self.updates = updates
        self.platform = platform
        self.entity = entity
    }

    func encodedJSON() -> String? {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func decode(fromJSON json: String?) -> PendingAction? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PendingAction.self, from: data)
    }

    // MARK: - Multiple pending actions per message
    //
    // A single coach turn can propose several risky writes (e.g. "delete these two
    // tasks"). They are persisted on `CoachMessage.pendingActionJSON` as a JSON
    // *array* so none are dropped. Decoding is backward-compatible: legacy rows hold
    // a single encoded object, which we still read as a one-element array.

    /// Encode a list of pending actions as a JSON array string (nil when empty).
    static func encodedJSONArray(_ actions: [PendingAction]) -> String? {
        guard !actions.isEmpty else { return nil }
        return (try? JSONEncoder().encode(actions)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Decode the persisted pending actions, tolerating both the new array form and
    /// the legacy single-object form.
    static func decodeArray(fromJSON json: String?) -> [PendingAction] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        if let array = try? JSONDecoder().decode([PendingAction].self, from: data) {
            return array
        }
        if let single = try? JSONDecoder().decode(PendingAction.self, from: data) {
            return [single]
        }
        return []
    }
}

/// Identifies the target of a platform-control confirm card.
struct PlatformActionPayload: Codable, Equatable {
    /// Sub-app / module id (matches `SubAppID.rawValue`).
    var targetId: String
    var displayName: String
}

/// Identifies a generic SwiftData entity for `deleteEntity` confirm cards.
struct EntityActionPayload: Codable, Equatable {
    /// Logical entity type, e.g. "task", "note", "medication".
    var entityType: String
    /// The entity's `id` UUID as a string.
    var id: String
    var displayName: String
}

/// Field updates for `updateActivitySession` (nil = leave unchanged).
struct ActivityUpdates: Codable, Equatable {
    var type: String?
    var notes: String?
    var distanceKm: Double?
    var durationMin: Double?
    var perceivedEffort: String?
    var startTime: String?
}
