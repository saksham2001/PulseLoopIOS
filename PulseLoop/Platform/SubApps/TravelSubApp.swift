import SwiftUI
import SwiftData

// MARK: - Travel SubApp
//
// Built-in module for planning trips: the coach searches the live web for flights,
// hotels/Airbnbs, activities, and restaurants, then organizes them into a Trip the
// user can review and book. Backed by `AppModule.travel`.

struct TravelSubApp: SubApp {
    var id: SubAppID { SubAppID(AppModule.travel.rawValue) }
    var displayName: String { AppModule.travel.name }
    var iconSystemName: String { AppModule.travel.icon }
    var summary: String { AppModule.travel.description }
    var version: String { "1.0.0" }
    var origin: SubAppOrigin { .builtIn }

    var models: [any PersistentModel.Type] { [Trip.self, TripItem.self, RewardCard.self] }

    @MainActor
    func aiTools(flags: CoachFeatureFlags) -> [AnyCoachTool] {
        var tools = TravelTools.readTools
        if flags.writeToolsEnabled { tools += TravelTools.writeTools }
        return tools
    }
}
