import SwiftUI
import SwiftData

// MARK: - Meditation SubApp (sessions + breathing)
//
// Migrated built-in (roadmap B12). Owns the `MeditationLog` model and covers the
// meditation/breathing screens. Not backed by a legacy `AppModule`, so it carries
// its own `SubAppID`.

struct MeditationSubApp: SubApp {
    var id: SubAppID { "meditation" }
    var displayName: String { "Meditation" }
    var iconSystemName: String { "leaf.fill" }
    var summary: String { "Meditation sessions and breathing exercises" }
    var origin: SubAppOrigin { .builtIn }

    var models: [any PersistentModel.Type] { [MeditationLog.self] }
}
