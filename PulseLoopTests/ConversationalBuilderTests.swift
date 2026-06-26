import Foundation
import SwiftData
import XCTest
@testable import PulseLoop

// MARK: - Conversational module builder tests (Life OS T2)
//
// "Describe it and it exists": a user describes a module, the coach authors a
// validated SubAppSpec, refining it bumps the version + re-validates, and
// save_subapp stages a preview + Install confirm card (never installs blindly).
// Confirming installs the module and opens it.

@MainActor
final class ConversationalBuilderTests: XCTestCase {

    private func builderFlags() -> CoachFeatureFlags {
        var s = CoachSettings.default
        s.enableSubAppBuilder = true
        s.enablePlatformControl = true
        return CoachFeatureFlags(settings: s, hasAPIKey: true)
    }

    private func ctx(_ c: ModelContext) -> ToolExecutionContext {
        ToolExecutionContext(modelContext: c, flags: builderFlags())
    }

    private func tool(_ name: String) throws -> AnyCoachTool {
        try XCTUnwrap(ToolRegistry(flags: builderFlags()).tool(named: name))
    }

    private func parse(_ result: ToolResult) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(result.jsonString.utf8)) as? [String: Any])
    }

    private let testID = "plunge_tracker_test"

    override func setUp() async throws {
        try await super.setUp()
        resetState()
    }

    override func tearDown() async throws {
        resetState()
        try await super.tearDown()
    }

    private func resetState() {
        SubAppBuilderDraftStore.shared.clear()
        SubAppRegistry.shared.uninstall(SubAppID(testID))
        UserSubAppStore.shared.delete(id: testID)
        SubAppRegistry.shared.loadUserSpecs()
        CoachNavigation.shared.requestedRoute = nil
    }

    // A valid snake_case spec payload for generate/refine.
    private func specJSON(displayName: String = "Cold Plunge", fields: String) -> Data {
        Data("""
        {
          "id": "\(testID)",
          "display_name": "\(displayName)",
          "icon": "drop.fill",
          "summary": "Track cold plunges.",
          "permissions": [],
          "entities": [
            { "name": "plunge", "label": "Plunge", "fields": [ \(fields) ] }
          ],
          "screens": [
            { "id": "list", "title": "Plunges", "kind": "list", "entity": "plunge" },
            { "id": "add", "title": "Add", "kind": "form", "entity": "plunge" }
          ]
        }
        """.utf8)
    }

    // MARK: Generate → validates + stages a draft

    func testGenerateStagesValidatedDraft() async throws {
        let result = try await tool("generate_subapp_spec").run(
            specJSON(fields: #"{ "name": "duration", "label": "Duration", "type": "number", "required": true, "options": [] }"#),
            ctx(try TestSupport.makeContext())
        )
        let obj = try parse(result)
        XCTAssertEqual(obj["ok"] as? Bool, true)
        XCTAssertEqual(obj["action"] as? String, "generated")
        let staged = try XCTUnwrap(SubAppBuilderDraftStore.shared.draft)
        XCTAssertEqual(staged.id, testID)
        XCTAssertNoThrow(try SubAppSpecValidator.validate(staged))
    }

    // MARK: Refine → bumps version + re-validates

    func testRefineBumpsVersionAndRevalidates() async throws {
        let c = try TestSupport.makeContext()
        _ = try await tool("generate_subapp_spec").run(
            specJSON(fields: #"{ "name": "duration", "label": "Duration", "type": "number", "required": true, "options": [] }"#),
            ctx(c)
        )
        let v0 = try XCTUnwrap(SubAppBuilderDraftStore.shared.draft).version

        // Refine: add a temperature field (full updated spec).
        let refined = try await tool("refine_subapp_spec").run(
            specJSON(fields: #"{ "name": "duration", "label": "Duration", "type": "number", "required": true, "options": [] }, { "name": "temp", "label": "Water Temp", "type": "number", "required": false, "options": [] }"#),
            ctx(c)
        )
        let obj = try parse(refined)
        XCTAssertEqual(obj["action"] as? String, "refined")
        let staged = try XCTUnwrap(SubAppBuilderDraftStore.shared.draft)
        XCTAssertGreaterThan(staged.version, v0, "a conversational edit should bump the version")
        XCTAssertEqual(staged.entities.first?.fields.count, 2)
        XCTAssertNoThrow(try SubAppSpecValidator.validate(staged))
    }

    func testBumpedVersionIsPureMonotonicPatchBump() {
        var spec = SubAppSpec(id: testID, displayName: "X", icon: "drop.fill", summary: "")
        spec.version = SemanticVersion(major: 1, minor: 0, patch: 0)
        SubAppBuilderDraftStore.shared.stage(spec)
        let bumped = SubAppBuilderTools.bumpedVersion(for: spec, isRefinement: true)
        XCTAssertEqual(bumped, SemanticVersion(major: 1, minor: 0, patch: 1))
        // A fresh generation never bumps.
        XCTAssertEqual(SubAppBuilderTools.bumpedVersion(for: spec, isRefinement: false), spec.version)
    }

    // MARK: Invalid spec rejected with actionable issues, never staged

    func testGenerateRejectsInvalidSpecWithActionableIssues() async throws {
        // Emoji icon → validator error; nothing should be staged.
        let bad = Data("""
        {
          "id": "\(testID)",
          "display_name": "Bad",
          "icon": "🔥",
          "summary": "",
          "permissions": [],
          "entities": [ { "name": "e", "label": "E", "fields": [ { "name": "n", "label": "N", "type": "text", "required": false, "options": [] } ] } ],
          "screens": [ { "id": "list", "title": "List", "kind": "list", "entity": "e" } ]
        }
        """.utf8)
        let result = try await tool("generate_subapp_spec").run(bad, ctx(try TestSupport.makeContext()))
        let obj = try parse(result)
        let error = try XCTUnwrap(obj["error"] as? String)
        XCTAssertTrue(error.contains("invalid"), "error should explain it's invalid: \(error)")
        XCTAssertNil(SubAppBuilderDraftStore.shared.draft, "invalid spec must not be staged")
    }

    // MARK: save_subapp stages an Install confirm card, does NOT install

    func testSaveSubAppQueuesInstallConfirmationWithoutInstalling() async throws {
        let c = try TestSupport.makeContext()
        _ = try await tool("generate_subapp_spec").run(
            specJSON(fields: #"{ "name": "duration", "label": "Duration", "type": "number", "required": true, "options": [] }"#),
            ctx(c)
        )
        let context = ctx(c)
        let result = try await tool("save_subapp").run(Data(#"{"reason":"looks good"}"#.utf8), context)
        let obj = try parse(result)
        XCTAssertEqual(obj["needs_confirmation"] as? Bool, true)
        XCTAssertEqual(context.pendingActions.count, 1)
        XCTAssertEqual(context.pendingActions.first?.kind, .installSubApp)
        XCTAssertEqual(context.pendingActions.first?.platform?.targetId, testID)
        // Not installed yet, and draft still staged so the card can preview it.
        XCTAssertFalse(SubAppRegistry.shared.isInstalled(SubAppID(testID)))
        XCTAssertNotNil(SubAppBuilderDraftStore.shared.draft)
    }

    func testSaveSubAppWithNoDraftErrors() async throws {
        let result = try await tool("save_subapp").run(Data(#"{"reason":"x"}"#.utf8), ctx(try TestSupport.makeContext()))
        let obj = try parse(result)
        XCTAssertNotNil(obj["error"] as? String)
    }

    // MARK: Confirming the install actually installs + opens the module

    func testConfirmingInstallActionInstallsAndNavigates() async throws {
        let c = try TestSupport.makeContext()
        _ = try await tool("generate_subapp_spec").run(
            specJSON(fields: #"{ "name": "duration", "label": "Duration", "type": "number", "required": true, "options": [] }"#),
            ctx(c)
        )
        let context = ctx(c)
        _ = try await tool("save_subapp").run(Data(#"{"reason":"go"}"#.utf8), context)
        let action = try XCTUnwrap(context.pendingActions.first)

        let message = PendingActionExecutor.execute(action, context: c)
        XCTAssertTrue(message.contains("Installed"))
        XCTAssertTrue(SubAppRegistry.shared.isInstalled(SubAppID(testID)), "confirm should install the module")
        XCTAssertNil(SubAppBuilderDraftStore.shared.draft, "draft cleared after install")
        XCTAssertEqual(CoachNavigation.shared.requestedRoute, .subApp(testID), "freshly installed module should open")
    }
}
