import XCTest
@testable import PulseLoop

/// T3 — community module gallery over HTTPTransport with bundled offline fallback,
/// tamper rejection in the catalog parser, and `.installed` origin attribution.
final class ModuleGalleryTests: XCTestCase {

    // MARK: Stub transport

    final class StubTransport: HTTPTransport, @unchecked Sendable {
        var data: Data
        var statusCode = 200
        var error: Error?
        private(set) var requests: [URLRequest] = []
        init(_ data: Data) { self.data = data }
        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            requests.append(request)
            if let error { throw error }
            let http = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
            return (data, http)
        }
    }

    // MARK: Fixtures

    private func sampleSpec(id: String = "gallery_sample") -> SubAppSpec {
        SubAppSpec(
            id: id,
            displayName: "Mood Tracker",
            icon: "face.smiling",
            summary: "Track how you feel each day.",
            author: "A Friend",
            permissions: [],
            entities: [
                EntitySpec(name: "mood", label: "Mood", fields: [
                    FieldSpec(name: "score", label: "Score", type: .rating, required: true),
                    FieldSpec(name: "logged_at", label: "Date", type: .date, required: true),
                ])
            ],
            screens: [
                ScreenSpec(id: "list", title: "Moods", kind: .list, entity: "mood"),
                ScreenSpec(id: "add", title: "Add", kind: .form, entity: "mood"),
            ]
        )
    }

    /// Build a server-style catalog JSON body wrapping a signed package.
    private func catalogBody(for spec: SubAppSpec, tampered: Bool = false) throws -> Data {
        let package = try SubAppPackager.makePackage(for: spec)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var packageObj = try JSONSerialization.jsonObject(with: encoder.encode(package)) as! [String: Any]
        if tampered {
            // Change the display name *without* re-signing → signature mismatch.
            var specObj = packageObj["spec"] as! [String: Any]
            specObj["displayName"] = "Hacked Name"
            packageObj["spec"] = specObj
        }
        let root: [String: Any] = [
            "modules": [[
                "category": "Mindfulness",
                "rating": 4.6,
                "rating_count": 42,
                "install_count": 1234,
                "changelog": [["version": spec.version.description, "notes": ["First release."], "date": "2026-06"]],
                "package": packageObj,
            ]]
        ]
        return try JSONSerialization.data(withJSONObject: root)
    }

    // MARK: Parser

    func testParseCatalogReturnsVerifiedListing() throws {
        let spec = sampleSpec()
        let listings = try HTTPModuleGalleryProvider.parseCatalog(catalogBody(for: spec))
        XCTAssertEqual(listings.count, 1)
        let listing = try XCTUnwrap(listings.first)
        XCTAssertEqual(listing.spec.id, spec.id)
        XCTAssertEqual(listing.category, "Mindfulness")
        XCTAssertEqual(listing.installCount, 1234)
        XCTAssertEqual(listing.communityRatingCount, 42)
        XCTAssertEqual(listing.changelog.first?.notes, ["First release."])
    }

    func testParseCatalogDropsTamperedPackage() throws {
        let listings = try HTTPModuleGalleryProvider.parseCatalog(catalogBody(for: sampleSpec(), tampered: true))
        XCTAssertTrue(listings.isEmpty, "A tampered package must never reach the install flow.")
    }

    func testParseCatalogThrowsOnGarbage() {
        XCTAssertThrowsError(try HTTPModuleGalleryProvider.parseCatalog(Data("not json".utf8)))
    }

    // MARK: Provider gating + fallback

    func testUnconfiguredProviderServesBundledFallback() async throws {
        let provider = HTTPModuleGalleryProvider(
            transport: StubTransport(Data()),
            baseURL: "REPLACE_ME", apiKey: "REPLACE_ME"
        )
        XCTAssertFalse(provider.isConfigured)
        let featured = try await provider.featured()
        XCTAssertFalse(featured.isEmpty, "Offline/unconfigured gallery must serve the bundled catalog.")
    }

    func testConfiguredProviderUsesLiveCatalog() async throws {
        let spec = sampleSpec()
        let provider = HTTPModuleGalleryProvider(
            transport: StubTransport(try catalogBody(for: spec)),
            baseURL: "https://gallery.example.com", apiKey: "realkey"
        )
        XCTAssertTrue(provider.isConfigured)
        let featured = try await provider.featured()
        XCTAssertEqual(featured.count, 1)
        XCTAssertEqual(featured.first?.spec.id, spec.id)
    }

    func testServerErrorFallsBackToBundled() async throws {
        let stub = StubTransport(Data())
        stub.statusCode = 500
        let provider = HTTPModuleGalleryProvider(
            transport: stub,
            baseURL: "https://gallery.example.com", apiKey: "realkey"
        )
        let featured = try await provider.featured()
        XCTAssertFalse(featured.isEmpty, "A 5xx must degrade to the bundled catalog, not blank the gallery.")
    }

    func testTransportErrorFallsBackToBundled() async throws {
        let stub = StubTransport(Data())
        stub.error = URLError(.notConnectedToInternet)
        let provider = HTTPModuleGalleryProvider(
            transport: stub,
            baseURL: "https://gallery.example.com", apiKey: "realkey"
        )
        let featured = try await provider.featured()
        XCTAssertFalse(featured.isEmpty)
    }

    func testSearchRequestCarriesQuery() throws {
        let provider = HTTPModuleGalleryProvider(baseURL: "https://gallery.example.com", apiKey: "k")
        let request = try XCTUnwrap(provider.catalogRequest(query: "mood"))
        let comps = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)
        XCTAssertTrue(request.url!.path.hasSuffix("/modules"))
        XCTAssertEqual(comps?.queryItems?.first { $0.name == "q" }?.value, "mood")
    }

    // MARK: .installed origin attribution

    @MainActor
    func testGalleryInstallTracksInstalledOrigin() throws {
        let store = UserSubAppStore.shared
        let spec = sampleSpec(id: "gallery_origin_test")
        defer { store.delete(id: spec.id); SubAppRegistry.shared.loadUserSpecs() }

        store.save(spec, origin: .installed)
        XCTAssertEqual(store.origin(for: spec.id), .installed)

        SubAppRegistry.shared.loadUserSpecs()
        let app = SubAppRegistry.shared.subApps.first { $0.id.rawValue == spec.id }
        XCTAssertEqual(app?.origin, .installed, "A gallery/imported install must be tracked as .installed for attribution.")
    }

    @MainActor
    func testBuilderSaveDefaultsToUserCreatedOrigin() throws {
        let store = UserSubAppStore.shared
        let spec = sampleSpec(id: "gallery_usercreated_test")
        defer { store.delete(id: spec.id); SubAppRegistry.shared.loadUserSpecs() }

        store.save(spec)
        XCTAssertEqual(store.origin(for: spec.id), .userCreated)
    }
}
