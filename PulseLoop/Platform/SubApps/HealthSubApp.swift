import SwiftUI
import SwiftData

// MARK: - Health SubApp (vitals hub: HR / SpO2 / device)
//
// Migrated built-in (roadmap B3). Owns the ring-device + on-demand measurement
// domain and the Health/Vitals dashboards. Like Activity it's a core health hub
// reached from the tab bar / Home rather than the module picker, so it carries its
// own `SubAppID`. Legacy `AppRoute.health` / `.vitals` still work.

enum HealthRoute: SubAppRoute {
    case dashboard
    case vitals
}

struct HealthSubApp: SubApp {
    var id: SubAppID { "health" }
    var displayName: String { "Health" }
    var iconSystemName: String { "heart.fill" }
    var summary: String { "Vitals, sleep, and activity from your ring" }
    var origin: SubAppOrigin { .builtIn }

    var models: [any PersistentModel.Type] {
        [Device.self, Measurement.self, DerivedUpdateRow.self, RawPacketRow.self]
    }

    var permissions: Set<SubAppPermission> { [.healthRead] }

    @MainActor
    func registerRoutes(with router: SubAppRouter) {
        router.registerDestination(for: HealthRoute.self) { route, ctx in
            switch route {
            case .dashboard:
                HealthView(path: ctx.path)
            case .vitals:
                VitalsView()
            }
        }
    }
}
