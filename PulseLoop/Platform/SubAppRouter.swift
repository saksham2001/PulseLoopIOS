import SwiftUI

// MARK: - SubAppRouter
//
// Pluggable navigation seam. Today every screen is reached through the single
// `AppRoute` enum + the `destinationView(for:)` switch in `Views/RootViews.swift`.
// That switch keeps working unchanged — this router is additive. Sub-apps register
// a destination type and a builder; `RootAppView` installs a
// `.navigationDestination` per registered type so navigating to a sub-app route
// resolves through the owning sub-app instead of the central switch.
//
// Migration plan: as built-in features become `SubApp` conformers (Phase B), their
// `AppRoute` cases move behind `registerDestination(...)` here and the central
// switch shrinks. Until then both paths coexist.

/// Marker for a value that can be pushed as a sub-app navigation destination.
/// Conformers are `Hashable` so they work with `NavigationStack` paths.
protocol SubAppRoute: Hashable {}

/// Context handed to a sub-app's destination builder so it can drive navigation
/// (push more routes, pop, etc.) using the shared `NavigationStack` path.
struct RouteContext {
    let path: Binding<NavigationPath>
}

@MainActor
final class SubAppRouter {
    static let shared = SubAppRouter()

    private init() {}

    /// Type-erased registration: the route's metatype → a modifier that attaches
    /// the matching `.navigationDestination`.
    private var installers: [ObjectIdentifier: (AnyView, Binding<NavigationPath>) -> AnyView] = [:]

    /// Register a destination builder for a concrete `SubAppRoute` type.
    func registerDestination<Route: SubAppRoute, Destination: View>(
        for routeType: Route.Type,
        @ViewBuilder destination: @escaping (Route, RouteContext) -> Destination
    ) {
        let key = ObjectIdentifier(routeType)
        installers[key] = { content, path in
            AnyView(
                content.navigationDestination(for: Route.self) { route in
                    destination(route, RouteContext(path: path))
                }
            )
        }
    }

    /// Apply every registered destination to a view. Called once by `RootAppView`.
    func install(on content: AnyView, path: Binding<NavigationPath>) -> AnyView {
        installers.values.reduce(content) { partial, installer in
            installer(partial, path)
        }
    }

    /// Whether any sub-app routes are registered (lets callers skip the modifier).
    var hasRoutes: Bool { !installers.isEmpty }
}

extension View {
    /// Installs all sub-app navigation destinations registered with `SubAppRouter`.
    /// Safe to call even when no sub-app routes exist yet.
    func subAppNavigationDestinations(path: Binding<NavigationPath>) -> some View {
        SubAppRouter.shared.install(on: AnyView(self), path: path)
    }
}
