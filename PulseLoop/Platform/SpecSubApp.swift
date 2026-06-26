import SwiftUI
import SwiftData

// MARK: - SpecSubApp — a SubApp conformer driven by a SubAppSpec (roadmap C4)
//
// This is the bridge that lets a declarative `SubAppSpec` behave like any other
// `SubApp`: it appears in the module picker, contributes no Swift-defined models
// (its data lives in the shared `DynamicSubAppRecord` table), and registers a single
// router destination that hosts the spec runtime. User-created (D2) and installed
// (F2) sub-apps will all be `SpecSubApp` instances — C4 proves the path by shipping
// one built-in spec (a Mood check-in) rendered entirely by the runtime.

/// Route into a spec-driven sub-app. Identified by spec id so multiple spec
/// sub-apps can coexist behind the same route type.
struct SpecSubAppRoute: SubAppRoute {
    let specID: String
}

struct SpecSubApp: SubApp {
    let spec: SubAppSpec

    var id: SubAppID { SubAppID(spec.id) }
    var displayName: String { spec.displayName }
    var iconSystemName: String { spec.icon }
    var summary: String { spec.summary }
    var version: String { spec.version.description }
    var author: String { spec.author }
    var origin: SubAppOrigin {
        // Built-in demo spec (C4) ships as `.builtIn`; user/installed specs override
        // by constructing with a different origin in later phases.
        explicitOrigin
    }

    private let explicitOrigin: SubAppOrigin

    init(spec: SubAppSpec, origin: SubAppOrigin = .builtIn) {
        self.spec = spec
        self.explicitOrigin = origin
    }

    var permissions: Set<SubAppPermission> { Set(spec.permissions) }

    // Dynamic specs store data in the shared `DynamicSubAppRecord` table, so they
    // contribute no bespoke models of their own.
    var models: [any PersistentModel.Type] { [] }

    @MainActor
    func registerRoutes(with router: SubAppRouter) {
        router.registerDestination(for: SpecSubAppRoute.self) { route, _ in
            SpecSubAppHost(specID: route.specID)
        }
    }
}

/// Hosts a spec runtime, resolving the active spec by id and binding it to the
/// SwiftData-backed record store from the environment.
struct SpecSubAppHost: View {
    let specID: String
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if !SubAppRegistry.shared.isInstalled(SubAppID(specID)) {
            InlineEmptyState(
                title: "Not installed",
                message: "Install this module from the catalog to use it."
            )
        } else if let spec = SpecSubAppCatalog.shared.spec(for: specID) {
            SubAppRuntimeView(spec: spec, store: SwiftDataSubAppRecordStore(context: modelContext))
        } else {
            InlineEmptyState(title: "Unavailable", message: "This sub-app could not be loaded.")
        }
    }
}

/// Registry of spec definitions available to the runtime (built-in demo specs plus,
/// later, user-created/installed specs loaded from disk). Lookups are by spec id.
@MainActor
final class SpecSubAppCatalog {
    static let shared = SpecSubAppCatalog()

    private var specsByID: [String: SubAppSpec] = [:]

    private init() {
        for spec in BuiltInSpecs.all {
            specsByID[spec.id] = spec
        }
    }

    func spec(for id: String) -> SubAppSpec? { specsByID[id] }

    func register(_ spec: SubAppSpec) { specsByID[spec.id] = spec }

    var allSpecs: [SubAppSpec] { Array(specsByID.values) }

    /// Convenience accessor for the built-in Mood spec (used at registry init).
    nonisolated static var moodCheckInSpec: SubAppSpec { BuiltInSpecs.moodCheckIn }
}

/// Nonisolated holder for built-in demo specs so they can be referenced from the
/// `SubAppRegistry`'s synchronous init.
enum BuiltInSpecs {
    static var all: [SubAppSpec] { [moodCheckIn] }

    /// A Mood check-in re-expressed as a declarative spec (C4). Mirrors the gist of
    /// the hand-written Mood feature: a rating + an optional note, listed by date.
    static let moodCheckIn = SubAppSpec(
        id: "mood_spec",
        displayName: "Mood Journal",
        icon: "face.smiling",
        summary: "A spec-driven mood check-in (proves the sub-app runtime)",
        author: "PulseLoop",
        permissions: [],
        entities: [
            EntitySpec(
                name: "checkin",
                label: "Check-in",
                fields: [
                    FieldSpec(name: "mood", label: "Mood", type: .rating, required: true),
                    FieldSpec(
                        name: "feeling",
                        label: "Feeling",
                        type: .selection,
                        options: ["Calm", "Happy", "Anxious", "Tired", "Energized", "Low"]
                    ),
                    FieldSpec(name: "note", label: "Note", type: .text),
                    FieldSpec(name: "when", label: "When", type: .date, required: true),
                ]
            )
        ],
        screens: [
            ScreenSpec(id: "list", title: "Mood Journal", kind: .list, entity: "checkin"),
            ScreenSpec(id: "form", title: "New Check-in", kind: .form, entity: "checkin"),
            ScreenSpec(id: "detail", title: "Check-in", kind: .detail, entity: "checkin"),
            ScreenSpec(id: "dashboard", title: "Overview", kind: .dashboard, entity: nil),
        ]
    )
}
