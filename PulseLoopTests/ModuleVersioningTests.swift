import Foundation
import SwiftData
import XCTest
@testable import PulseLoop

// MARK: - Module versioning + AI-Notes tool tests (Notes roadmap F3)
//
// Covers the per-module version system (compare/parse, availableUpdate detection,
// apply-update-once + version stamping) and the new Notes Coach tools
// (summarize/collection/link) plus the typed-capture parser already covered by
// VoiceCaptureRouterTests. UserDefaults-backed version state is snapshotted and
// restored so tests don't leak across runs.
@MainActor
final class ModuleVersioningTests: XCTestCase {

    private let installedVersionsKey = "pulseloop.modules.installedVersions.v1"
    private let versionBackfillKey = "pulseloop.modules.versionBackfill.v1"
    private let enabledKey = "enabledModules"

    private var savedVersions: Data?
    private var savedBackfill: Any?
    private var savedEnabled: Data?

    override func setUp() {
        super.setUp()
        let d = UserDefaults.standard
        savedVersions = d.data(forKey: installedVersionsKey)
        savedBackfill = d.object(forKey: versionBackfillKey)
        savedEnabled = d.data(forKey: enabledKey)
        d.removeObject(forKey: installedVersionsKey)
        d.removeObject(forKey: versionBackfillKey)
        d.removeObject(forKey: enabledKey)
    }

    override func tearDown() {
        let d = UserDefaults.standard
        if let savedVersions { d.set(savedVersions, forKey: installedVersionsKey) } else { d.removeObject(forKey: installedVersionsKey) }
        if let savedBackfill { d.set(savedBackfill, forKey: versionBackfillKey) } else { d.removeObject(forKey: versionBackfillKey) }
        if let savedEnabled { d.set(savedEnabled, forKey: enabledKey) } else { d.removeObject(forKey: enabledKey) }
        super.tearDown()
    }

    private func flags() -> CoachFeatureFlags {
        var s = CoachSettings.default
        s.enableWriteTools = true
        s.enablePlatformControl = true
        return CoachFeatureFlags(settings: s, hasAPIKey: true)
    }

    private func parse(_ result: ToolResult) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(result.jsonString.utf8)) as? [String: Any])
    }

    // MARK: SemanticVersion compare + parse

    func testSemanticVersionOrdering() {
        XCTAssertLessThan(SemanticVersion(major: 1, minor: 0, patch: 0), SemanticVersion(major: 1, minor: 0, patch: 1))
        XCTAssertLessThan(SemanticVersion(major: 1, minor: 2, patch: 9), SemanticVersion(major: 1, minor: 3, patch: 0))
        XCTAssertLessThan(SemanticVersion(major: 1, minor: 9, patch: 9), SemanticVersion(major: 2, minor: 0, patch: 0))
        XCTAssertEqual(SemanticVersion("2.4.6"), SemanticVersion(major: 2, minor: 4, patch: 6))
    }

    func testSemanticVersionParseRejectsMalformed() {
        XCTAssertNil(SemanticVersion("1.0"))
        XCTAssertNil(SemanticVersion("v1.0.0"))
        XCTAssertNil(SemanticVersion("1.x.0"))
    }

    func testParseOrDefaultFallsBackToOneZeroZero() {
        XCTAssertEqual(SemanticVersion.parseOrDefault(nil), SemanticVersion(major: 1, minor: 0, patch: 0))
        XCTAssertEqual(SemanticVersion.parseOrDefault("garbage"), SemanticVersion(major: 1, minor: 0, patch: 0))
        XCTAssertEqual(SemanticVersion.parseOrDefault("3.1.4"), SemanticVersion(major: 3, minor: 1, patch: 4))
    }

    // MARK: availableUpdate detection

    func testNoUpdateWhenInstalledAtCurrentVersion() {
        let registry = SubAppRegistry.shared
        let id = SubAppID(AppModule.notes.rawValue)
        registry.install(id) // stamps current build version
        XCTAssertNil(registry.availableUpdate(for: id))
        XCTAssertFalse(registry.modulesWithUpdates.contains { $0.id == id })
    }

    func testUpdateDetectedWhenInstalledVersionIsOlder() {
        let registry = SubAppRegistry.shared
        let id = SubAppID(AppModule.notes.rawValue)
        registry.install(id)
        // Pretend the user installed an older build.
        registry.recordInstalledVersion(id, SemanticVersion(major: 0, minor: 9, patch: 0))
        let update = registry.availableUpdate(for: id)
        XCTAssertNotNil(update, "An older installed version should surface an update")
        XCTAssertEqual(update, registry.subApp(id: id)?.semanticVersion)
        XCTAssertTrue(registry.modulesWithUpdates.contains { $0.id == id })
    }

    func testUninstalledModuleNeverShowsUpdate() {
        let registry = SubAppRegistry.shared
        let id = SubAppID(AppModule.notes.rawValue)
        // Not installed.
        XCTAssertNil(registry.availableUpdate(for: id))
    }

    // MARK: applyUpdate stamps the new version (migration-once)

    func testApplyUpdateStampsCurrentVersionAndClearsUpdate() throws {
        let c = try TestSupport.makeContext()
        let registry = SubAppRegistry.shared
        let id = SubAppID(AppModule.notes.rawValue)
        registry.install(id)
        registry.recordInstalledVersion(id, SemanticVersion(major: 0, minor: 1, patch: 0))

        let target = try XCTUnwrap(registry.subApp(id: id)?.semanticVersion)
        let applied = registry.applyUpdate(id, context: c)
        XCTAssertEqual(applied, target)
        // Installed version now matches the build → no further update, and a second
        // apply is a no-op (migration runs once).
        XCTAssertEqual(registry.installedVersion(of: id), target)
        XCTAssertNil(registry.availableUpdate(for: id))
        XCTAssertNil(registry.applyUpdate(id, context: c))
    }

    func testBackfillStampsInstalledModulesWithoutSpuriousUpdates() {
        let registry = SubAppRegistry.shared
        let id = SubAppID(AppModule.notes.rawValue)
        registry.install(id)
        // Simulate a pre-versioning install: drop the recorded version, reset backfill.
        UserDefaults.standard.removeObject(forKey: installedVersionsKey)
        UserDefaults.standard.removeObject(forKey: versionBackfillKey)

        registry.runVersionBackfill()
        XCTAssertEqual(registry.installedVersion(of: id), registry.subApp(id: id)?.semanticVersion)
        XCTAssertNil(registry.availableUpdate(for: id))
    }

    // MARK: update_module Coach tool

    func testListModuleUpdatesReportsPendingUpdate() async throws {
        let c = try TestSupport.makeContext()
        let registry = SubAppRegistry.shared
        let id = SubAppID(AppModule.notes.rawValue)
        registry.install(id)
        registry.recordInstalledVersion(id, SemanticVersion(major: 0, minor: 5, patch: 0))

        let tool = try XCTUnwrap(ToolRegistry(flags: flags()).tool(named: "list_module_updates"))
        let res = try parse(try await tool.run(Data("{}".utf8), ToolExecutionContext(modelContext: c, flags: flags())))
        let updates = try XCTUnwrap(res["updates"] as? [[String: Any]])
        XCTAssertTrue(updates.contains { ($0["id"] as? String) == id.rawValue })
    }

    func testUpdateModuleAppliesWhenNotRisky() async throws {
        let c = try TestSupport.makeContext()
        let registry = SubAppRegistry.shared
        let id = SubAppID(AppModule.notes.rawValue)
        registry.install(id)
        registry.recordInstalledVersion(id, SemanticVersion(major: 0, minor: 5, patch: 0))

        let tool = try XCTUnwrap(ToolRegistry(flags: flags()).tool(named: "update_module"))
        let ctx = ToolExecutionContext(modelContext: c, flags: flags())
        let res = try parse(try await tool.run(Data(#"{"module_id":"\#(id.rawValue)","reason":"newer build"}"#.utf8), ctx))
        // Built-in Notes has no risky migration → applies immediately.
        XCTAssertEqual(res["applied"] as? Bool, true)
        XCTAssertEqual(registry.installedVersion(of: id), registry.subApp(id: id)?.semanticVersion)
    }

    // MARK: Tracker module version bump (Tracker roadmap A3)

    func testProtocolAndNutritionReportBumpedVersion() {
        let registry = SubAppRegistry.shared
        let target = SemanticVersion(major: 1, minor: 1, patch: 0)
        let protocolApp = registry.subApp(id: SubAppID(AppModule.protocol_.rawValue))
        let nutritionApp = registry.subApp(id: SubAppID(AppModule.nutrition.rawValue))
        XCTAssertEqual(protocolApp?.semanticVersion, target, "Protocol sub-app should be bumped to 1.1.0")
        XCTAssertEqual(nutritionApp?.semanticVersion, target, "Nutrition sub-app should be bumped to 1.1.0")
    }

    func testTrackerModulesSurfaceUpdateFromOlderInstall() {
        let registry = SubAppRegistry.shared
        for module in [AppModule.protocol_, AppModule.nutrition] {
            let id = SubAppID(module.rawValue)
            registry.install(id)
            registry.recordInstalledVersion(id, SemanticVersion(major: 1, minor: 0, patch: 0))
            let update = registry.availableUpdate(for: id)
            XCTAssertEqual(update, SemanticVersion(major: 1, minor: 1, patch: 0),
                           "\(module.rawValue) at 1.0.0 should surface a 1.1.0 update")
            XCTAssertTrue(registry.modulesWithUpdates.contains { $0.id == id })
        }
    }

    // MARK: Voice module version bump (Voice roadmap A3)

    func testAICaptureReportsBumpedVoiceVersion() {
        let registry = SubAppRegistry.shared
        let id = SubAppID(AppModule.aiCapture.rawValue)
        let app = registry.subApp(id: id)
        XCTAssertEqual(app?.semanticVersion, SemanticVersion(major: 1, minor: 1, patch: 0),
                       "AI Capture sub-app should be bumped to 1.1.0 for the voice engine layer")
    }

    func testAICaptureSurfacesUpdateFromOlderInstall() {
        let registry = SubAppRegistry.shared
        let id = SubAppID(AppModule.aiCapture.rawValue)
        registry.install(id)
        registry.recordInstalledVersion(id, SemanticVersion(major: 1, minor: 0, patch: 0))
        XCTAssertEqual(registry.availableUpdate(for: id), SemanticVersion(major: 1, minor: 1, patch: 0))
        XCTAssertTrue(registry.modulesWithUpdates.contains { $0.id == id })
    }
}

// MARK: - Notes Coach tool tests

@MainActor
final class NoteToolsTests: XCTestCase {

    private func flags() -> CoachFeatureFlags {
        var s = CoachSettings.default
        s.enableWriteTools = true
        return CoachFeatureFlags(settings: s, hasAPIKey: true)
    }

    private func parse(_ result: ToolResult) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(result.jsonString.utf8)) as? [String: Any])
    }

    private func makeNote(in c: ModelContext, title: String, body: [String]) -> Note {
        let note = Note(title: title)
        c.insert(note)
        for (i, line) in body.enumerated() {
            let block = NoteBlock(noteId: note.id, order: i, kind: .paragraph, content: line)
            c.insert(block)
            note.blocks.append(block)
        }
        c.saveOrLog("test")
        return note
    }

    func testSetNoteCollectionFindsOrCreatesByName() async throws {
        let c = try TestSupport.makeContext()
        let note = makeNote(in: c, title: "Trip ideas", body: ["Visit Kyoto"])
        let tool = try XCTUnwrap(ToolRegistry(flags: flags()).tool(named: "set_note_collection"))

        let json = #"{"note_id":"\#(note.id.uuidString)","collection_id":null,"collection_name":"Travel"}"#
        let res = try parse(try await tool.run(Data(json.utf8), ToolExecutionContext(modelContext: c, flags: flags())))
        XCTAssertEqual(res["ok"] as? Bool, true)
        XCTAssertNotNil(note.collectionId)

        let cols = try c.fetch(FetchDescriptor<Collection>())
        XCTAssertTrue(cols.contains { $0.name == "Travel" && $0.id == note.collectionId })

        // Filing a second note into the same name reuses the collection (no dup).
        let note2 = makeNote(in: c, title: "More trips", body: ["Visit Oslo"])
        let json2 = #"{"note_id":"\#(note2.id.uuidString)","collection_id":null,"collection_name":"travel"}"#
        _ = try await tool.run(Data(json2.utf8), ToolExecutionContext(modelContext: c, flags: flags()))
        XCTAssertEqual(note2.collectionId, note.collectionId)
        XCTAssertEqual(try c.fetch(FetchDescriptor<Collection>()).filter { $0.name.lowercased() == "travel" }.count, 1)
    }

    func testLinkNotesCreatesAndRemovesLink() async throws {
        let c = try TestSupport.makeContext()
        let a = makeNote(in: c, title: "A", body: ["alpha"])
        let b = makeNote(in: c, title: "B", body: ["beta"])
        let tool = try XCTUnwrap(ToolRegistry(flags: flags()).tool(named: "link_notes"))

        let link = #"{"note_id":"\#(a.id.uuidString)","target_note_id":"\#(b.id.uuidString)","unlink":false}"#
        _ = try await tool.run(Data(link.utf8), ToolExecutionContext(modelContext: c, flags: flags()))
        XCTAssertTrue(a.linkedNoteIds.contains(b.id))

        let unlink = #"{"note_id":"\#(a.id.uuidString)","target_note_id":"\#(b.id.uuidString)","unlink":true}"#
        _ = try await tool.run(Data(unlink.utf8), ToolExecutionContext(modelContext: c, flags: flags()))
        XCTAssertFalse(a.linkedNoteIds.contains(b.id))
    }

    func testLinkNotesRejectsSelfLink() async throws {
        let c = try TestSupport.makeContext()
        let a = makeNote(in: c, title: "A", body: ["alpha"])
        let tool = try XCTUnwrap(ToolRegistry(flags: flags()).tool(named: "link_notes"))
        let json = #"{"note_id":"\#(a.id.uuidString)","target_note_id":"\#(a.id.uuidString)","unlink":false}"#
        let res = try parse(try await tool.run(Data(json.utf8), ToolExecutionContext(modelContext: c, flags: flags())))
        XCTAssertNotNil(res["error"], "Self-linking should be rejected")
        XCTAssertFalse(a.linkedNoteIds.contains(a.id))
    }

    func testListNotesSearchesTitleAndBody() async throws {
        let c = try TestSupport.makeContext()
        _ = makeNote(in: c, title: "Groceries", body: ["milk", "eggs"])
        _ = makeNote(in: c, title: "Work", body: ["finish the quarterly report"])
        let tool = try XCTUnwrap(ToolRegistry(flags: flags()).tool(named: "list_notes"))

        // Body-only match.
        let res = try parse(try await tool.run(Data(#"{"query":"quarterly","tag":null,"limit":null}"#.utf8),
                                               ToolExecutionContext(modelContext: c, flags: flags())))
        let rows = try XCTUnwrap(res["notes"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?["title"] as? String, "Work")
    }
}
