import Foundation
import Combine

// MARK: - Sub-App Registry (roadmap F2)
//
// A browsable catalog of shareable sub-apps. Installing transfers the signed
// declarative spec (F1) — never code — and always runs through verification +
// guardrails + permission review. `SubAppRegistryService` is the seam: v1 ships a
// `BundledSubAppRegistryService` (curated, on-device, signed at runtime) so the
// browse/install/rate flow is fully exercisable; F3 / backend (E3) swaps in a
// network-backed service that returns server-signed packages.

/// One entry in the registry.
struct RegistryListing: Identifiable, Hashable {
    var id: String { package.spec.id }
    /// The signed, shareable package (verified before install).
    let package: SubAppPackage
    /// Short category for grouping/browse.
    let category: String
    /// Aggregate community rating (0...5), excluding the local user's rating.
    let communityRating: Double
    let communityRatingCount: Int
    /// How many times this module has been installed (community signal).
    var installCount: Int
    /// Per-version changelog, newest first, for an informed install/update decision.
    var changelog: [SubAppChangelogEntry]

    var spec: SubAppSpec { package.spec }

    init(
        package: SubAppPackage,
        category: String,
        communityRating: Double,
        communityRatingCount: Int,
        installCount: Int = 0,
        changelog: [SubAppChangelogEntry] = []
    ) {
        self.package = package
        self.category = category
        self.communityRating = communityRating
        self.communityRatingCount = communityRatingCount
        self.installCount = installCount
        self.changelog = changelog
    }
}

/// Source of registry listings. Async so a network-backed impl drops in later.
protocol SubAppRegistryService: Sendable {
    func featured() async throws -> [RegistryListing]
    func search(_ query: String) async throws -> [RegistryListing]
}

/// Local, curated registry. Specs are defined as values and signed at runtime so the
/// install path (verify → validate → guardrail → permission review) is identical to a
/// remote source. Network errors / latency are simulated minimally (none here).
struct BundledSubAppRegistryService: SubAppRegistryService {
    func featured() async throws -> [RegistryListing] { try Self.listings }

    func search(_ query: String) async throws -> [RegistryListing] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return try Self.listings }
        return try Self.listings.filter {
            $0.spec.displayName.lowercased().contains(q)
                || $0.spec.summary.lowercased().contains(q)
                || $0.category.lowercased().contains(q)
        }
    }

    // MARK: Curated catalog

    private static let catalog: [(spec: SubAppSpec, category: String, rating: Double, count: Int, installs: Int)] = [
        (RegistrySpecs.waterIntake, "Health", 4.7, 213, 5120),
        (RegistrySpecs.gratitudeJournal, "Mindfulness", 4.9, 156, 3340),
        (RegistrySpecs.readingLog, "Productivity", 4.5, 88, 1980),
    ]

    private static let listings: [RegistryListing] = {
        catalog.compactMap { item in
            guard let package = try? SubAppPackager.makePackage(for: item.spec) else { return nil }
            return RegistryListing(
                package: package,
                category: item.category,
                communityRating: item.rating,
                communityRatingCount: item.count,
                installCount: item.installs,
                changelog: [SubAppChangelogEntry(item.spec.version.description, ["Initial community release."])]
            )
        }
    }()
}

/// Curated example specs available in the v1 registry. Slug ids must not collide with
/// built-ins (the guardrail layer enforces this on install too).
enum RegistrySpecs {
    static let waterIntake = SubAppSpec(
        id: "registry_water_intake",
        displayName: "Water Intake",
        icon: "drop.fill",
        summary: "Log glasses of water and see your daily hydration.",
        author: "PulseLoop Community",
        permissions: [],
        entities: [
            EntitySpec(name: "drink", label: "Drink", fields: [
                FieldSpec(name: "glasses", label: "Glasses", type: .integer, required: true),
                FieldSpec(name: "logged_at", label: "Time", type: .date, required: true),
                FieldSpec(name: "note", label: "Note", type: .text),
            ])
        ],
        screens: [
            ScreenSpec(id: "log", title: "Hydration", kind: .list, entity: "drink"),
            ScreenSpec(id: "add", title: "Add drink", kind: .form, entity: "drink"),
            ScreenSpec(id: "summary", title: "Overview", kind: .dashboard, entity: nil),
        ]
    )

    static let gratitudeJournal = SubAppSpec(
        id: "registry_gratitude",
        displayName: "Gratitude Journal",
        icon: "heart.text.square",
        summary: "Note three things you're grateful for each day.",
        author: "PulseLoop Community",
        permissions: [],
        entities: [
            EntitySpec(name: "entry", label: "Entry", fields: [
                FieldSpec(name: "text", label: "Grateful for", type: .text, required: true),
                FieldSpec(name: "mood", label: "Mood", type: .rating),
                FieldSpec(name: "logged_at", label: "Date", type: .date, required: true),
            ])
        ],
        screens: [
            ScreenSpec(id: "entries", title: "Gratitude", kind: .list, entity: "entry"),
            ScreenSpec(id: "add", title: "New entry", kind: .form, entity: "entry"),
            ScreenSpec(id: "detail", title: "Entry", kind: .detail, entity: "entry"),
        ]
    )

    static let readingLog = SubAppSpec(
        id: "registry_reading_log",
        displayName: "Reading Log",
        icon: "book.fill",
        summary: "Track books you're reading and how far you've gotten.",
        author: "PulseLoop Community",
        permissions: [],
        entities: [
            EntitySpec(name: "book", label: "Book", fields: [
                FieldSpec(name: "title", label: "Title", type: .text, required: true),
                FieldSpec(name: "author", label: "Author", type: .text),
                FieldSpec(name: "progress", label: "Progress %", type: .integer),
                FieldSpec(name: "status", label: "Status", type: .selection,
                          options: ["To read", "Reading", "Finished"]),
                FieldSpec(name: "rating", label: "Rating", type: .rating),
            ])
        ],
        screens: [
            ScreenSpec(id: "shelf", title: "Bookshelf", kind: .list, entity: "book"),
            ScreenSpec(id: "add", title: "Add book", kind: .form, entity: "book"),
            ScreenSpec(id: "detail", title: "Book", kind: .detail, entity: "book"),
        ]
    )
}

/// Stores the local user's star ratings + which registry sub-apps they installed.
/// UserDefaults-backed; a server ledger replaces this with the backend (E3/F3).
@MainActor
final class SubAppRegistryStore: ObservableObject {
    static let shared = SubAppRegistryStore()

    private static let ratingsKey = "pulseloop.registry.ratings.v1"
    private static let installedKey = "pulseloop.registry.installed.v1"
    private static let versionsKey = "pulseloop.registry.installedVersions.v1"
    private let defaults: UserDefaults

    /// Map of listing id → the user's own 1...5 rating.
    @Published private(set) var myRatings: [String: Int] = [:]
    /// Set of listing ids the user installed from the registry.
    @Published private(set) var installedIDs: Set<String> = []
    /// Map of installed listing id → the spec version string installed. Drives the
    /// "update available" check (F3).
    @Published private(set) var installedVersions: [String: String] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.ratingsKey),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            myRatings = decoded
        }
        if let ids = defaults.array(forKey: Self.installedKey) as? [String] {
            installedIDs = Set(ids)
        }
        if let data = defaults.data(forKey: Self.versionsKey),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            installedVersions = decoded
        }
    }

    func rating(for id: String) -> Int? { myRatings[id] }
    func isInstalled(_ id: String) -> Bool { installedIDs.contains(id) }
    func installedVersion(for id: String) -> SemanticVersion? {
        installedVersions[id].flatMap(SemanticVersion.init)
    }

    /// Whether the listing offers a newer version than what's installed.
    func updateAvailable(for listing: RegistryListing) -> Bool {
        guard isInstalled(listing.id), let installed = installedVersion(for: listing.id) else { return false }
        return listing.spec.version > installed
    }

    func rate(_ id: String, stars: Int) {
        myRatings[id] = max(1, min(5, stars))
        persistRatings()
    }

    func markInstalled(_ id: String, version: SemanticVersion) {
        installedIDs.insert(id)
        installedVersions[id] = version.description
        persistInstalled()
    }

    func markUninstalled(_ id: String) {
        installedIDs.remove(id)
        installedVersions.removeValue(forKey: id)
        persistInstalled()
    }

    private func persistRatings() {
        if let data = try? JSONEncoder().encode(myRatings) {
            defaults.set(data, forKey: Self.ratingsKey)
        }
    }

    private func persistInstalled() {
        defaults.set(Array(installedIDs), forKey: Self.installedKey)
        if let data = try? JSONEncoder().encode(installedVersions) {
            defaults.set(data, forKey: Self.versionsKey)
        }
    }
}
