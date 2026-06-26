import SwiftUI
import SwiftData

// MARK: - Symptoms & Labs SubApp
//
// Migrated built-in (roadmap B13). Owns the `SymptomLog` and `LabResult` models and
// the symptom/lab tracking screens. Not backed by a legacy `AppModule`, so it
// carries its own `SubAppID`.

struct SymptomsLabsSubApp: SubApp {
    var id: SubAppID { "symptoms_labs" }
    var displayName: String { "Symptoms & Labs" }
    var iconSystemName: String { "cross.case.fill" }
    var summary: String { "Track symptoms and lab results" }
    var origin: SubAppOrigin { .builtIn }

    var models: [any PersistentModel.Type] { [SymptomLog.self, LabResult.self] }
}
