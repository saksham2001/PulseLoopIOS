import SwiftUI
import SwiftData

// MARK: - Friends / Accountability SubApp
//
// Migrated built-in (roadmap B15). Backed by the legacy `AppModule.accountability`
// module. Owns the social graph: friends, their shared activity, wishlists,
// upcoming events, and travel plans. Provides router-native destinations for the
// Friends feed and the user's own profile. Legacy `AppRoute` cases still work.

enum FriendsRoute: SubAppRoute {
    case friends
    case profile
}

struct FriendsSubApp: SubApp {
    var id: SubAppID { SubAppID(AppModule.accountability.rawValue) }
    var displayName: String { AppModule.accountability.name }
    var iconSystemName: String { AppModule.accountability.icon }
    var summary: String { AppModule.accountability.description }
    var origin: SubAppOrigin { .builtIn }

    var models: [any PersistentModel.Type] {
        [
            Friend.self,
            FriendActivity.self,
            Wishlist.self,
            WishlistItem.self,
            FriendEvent.self,
            TravelPlan.self,
        ]
    }

    @MainActor
    func registerRoutes(with router: SubAppRouter) {
        router.registerDestination(for: FriendsRoute.self) { route, ctx in
            switch route {
            case .friends:
                FriendsView(path: ctx.path)
            case .profile:
                ProfileView()
            }
        }
    }
}
