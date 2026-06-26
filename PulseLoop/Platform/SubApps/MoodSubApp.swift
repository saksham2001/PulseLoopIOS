import SwiftUI
import SwiftData

// MARK: - Mood SubApp (daily mood + energy check-ins)
//
// Migrated built-in (roadmap B10). Backed by the legacy `AppModule.moodTracking`
// module. Owns the `MoodEntry` model. The mood UI lives in the wellness tracking
// screens (reached from the tracker / home), so no standalone route yet.

struct MoodSubApp: SubApp {
    var id: SubAppID { SubAppID(AppModule.moodTracking.rawValue) }
    var displayName: String { AppModule.moodTracking.name }
    var iconSystemName: String { AppModule.moodTracking.icon }
    var summary: String { AppModule.moodTracking.description }
    var origin: SubAppOrigin { .builtIn }

    var models: [any PersistentModel.Type] { [MoodEntry.self] }
}
