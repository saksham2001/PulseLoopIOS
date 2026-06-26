import SwiftUI
import SwiftData

// MARK: - Day Plan SubApp
//
// Migrated built-in (roadmap B17). Backed by the legacy `AppModule.dayPlan` module.
// Owns the AI-generated daily plan: timeline blocks the coach assembles from the
// user's protocol, tasks, and energy. Registers a router-native destination for the
// plan screen. Legacy `AppRoute` cases still work.

enum DayPlanRoute: SubAppRoute {
    case plan
}

struct DayPlanSubApp: SubApp {
    var id: SubAppID { SubAppID(AppModule.dayPlan.rawValue) }
    var displayName: String { AppModule.dayPlan.name }
    var iconSystemName: String { AppModule.dayPlan.icon }
    var summary: String { AppModule.dayPlan.description }
    var origin: SubAppOrigin { .builtIn }

    var models: [any PersistentModel.Type] { [DayPlan.self, DayPlanAction.self] }

    @MainActor
    func registerRoutes(with router: SubAppRouter) {
        router.registerDestination(for: DayPlanRoute.self) { route, _ in
            switch route {
            case .plan:
                DayPlanView()
            }
        }
    }
}
