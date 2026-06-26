import SwiftUI
import SwiftData

// MARK: - Activity SubApp (cardio / movement / GPS)
//
// Migrated built-in (roadmap B2). Owns the cardio Activity domain: session/sample/
// GPS/event models and the recording flow routes. Unlike most built-ins this isn't
// backed by a legacy `AppModule` — Activity is reached from Health, not the module
// picker — so it carries its own `SubAppID`. Legacy `AppRoute` cases still work.

/// Sub-app navigation destinations for Activity. (The legacy `AppRoute` equivalents
/// remain for existing call sites; these are the router-native versions.)
enum ActivityRoute: SubAppRoute {
    case dashboard
    case recordSelect
    case recordLive(UUID)
    case recordSummary(UUID)
    case detail(UUID)
}

struct ActivitySubApp: SubApp {
    var id: SubAppID { "activity" }
    var displayName: String { "Activity" }
    var iconSystemName: String { "figure.run" }
    var summary: String { "Record workouts and track movement from your ring" }
    var origin: SubAppOrigin { .builtIn }

    var models: [any PersistentModel.Type] {
        [
            ActivitySession.self,
            ActivitySample.self,
            ActivityGpsPoint.self,
            ActivityEvent.self,
            ActivitySensorPollEvent.self,
            ActivityDaily.self,
        ]
    }

    var permissions: Set<SubAppPermission> { [.healthRead, .location] }

    @MainActor
    func registerRoutes(with router: SubAppRouter) {
        router.registerDestination(for: ActivityRoute.self) { route, ctx in
            switch route {
            case .dashboard:
                ActivityView(path: ctx.path)
            case .recordSelect:
                RecordSelectView(path: ctx.path)
            case let .recordLive(id):
                RecordLiveView(sessionId: id, path: ctx.path)
            case let .recordSummary(id):
                RecordSummaryView(sessionId: id, path: ctx.path)
            case let .detail(id):
                ActivityDetailView(sessionId: id)
            }
        }
    }
}
