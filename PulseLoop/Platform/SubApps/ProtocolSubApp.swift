import SwiftUI
import SwiftData

// MARK: - Protocol SubApp (supplements / medications / peptides)
//
// Migrated built-in (roadmap B5). Backed by the legacy `AppModule.protocol_` module.
// Owns the protocol domain models. The protocol UI currently lives inside
// `TrackerView` (reached via a tab switch), so this sub-app contributes no routes
// yet — it owns its models and identity. Routes can move here when the protocol
// screen is extracted to a standalone destination.

struct ProtocolSubApp: SubApp {
    var id: SubAppID { SubAppID(AppModule.protocol_.rawValue) }
    var displayName: String { AppModule.protocol_.name }
    var iconSystemName: String { AppModule.protocol_.icon }
    var summary: String { AppModule.protocol_.description }
    var version: String { "1.1.0" }
    var origin: SubAppOrigin { .builtIn }

    var models: [any PersistentModel.Type] {
        [Medication.self, MedicationLog.self, Routine.self, RoutineStep.self, CustomProductInfo.self]
    }

    var permissions: Set<SubAppPermission> { [.notifications] }
}
