import SwiftUI
import SwiftData

// MARK: - Journal SubApp (daily metric journaling)
//
// Migrated built-in (roadmap B9). Owns the daily-journal domain (per-day metric
// toggles + values). Not backed by a legacy `AppModule`, so it carries its own
// `SubAppID`. Legacy `AppRoute.journal` still works.

enum JournalRoute: SubAppRoute {
    case dashboard
}

struct JournalSubApp: SubApp {
    var id: SubAppID { "journal" }
    var displayName: String { "Journal" }
    var iconSystemName: String { "book.closed.fill" }
    var summary: String { "Daily journaling of habits and metrics" }
    var origin: SubAppOrigin { .builtIn }

    var models: [any PersistentModel.Type] {
        [JournalDay.self, JournalMetricEntry.self]
    }

    @MainActor
    func registerRoutes(with router: SubAppRouter) {
        router.registerDestination(for: JournalRoute.self) { route, _ in
            switch route {
            case .dashboard:
                JournalView()
            }
        }
    }
}
