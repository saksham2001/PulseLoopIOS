import SwiftUI
import SwiftData

// MARK: - Stress SubApp (stress level logging)
//
// Migrated built-in (roadmap B11). Owns the `StressLog` model. Stress UI lives in
// the wellness tracking screens, so no standalone route yet. Not backed by a legacy
// `AppModule`, so it carries its own `SubAppID`.

struct StressSubApp: SubApp {
    var id: SubAppID { "stress" }
    var displayName: String { "Stress" }
    var iconSystemName: String { "waveform.path.ecg" }
    var summary: String { "Log stress levels and triggers" }
    var origin: SubAppOrigin { .builtIn }

    var models: [any PersistentModel.Type] { [StressLog.self] }
}
