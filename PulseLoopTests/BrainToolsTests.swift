import Foundation
import SwiftData
import XCTest
@testable import PulseLoop

/// Tests for the "ultimate brain" tool surface added across Phases A–F:
/// tasks, notes, protocol, daily-life, navigation, profile, and spec records.
/// Network-free — exercises the deterministic tool logic and confirm-card flow.
@MainActor
final class BrainToolsTests: XCTestCase {

    private func flags(write: Bool = true, platform: Bool = true) -> CoachFeatureFlags {
        var s = CoachSettings.default
        s.enableWriteTools = write
        s.enablePlatformControl = platform
        return CoachFeatureFlags(settings: s, hasAPIKey: true)
    }

    private func ctx(_ c: ModelContext, _ f: CoachFeatureFlags? = nil) -> ToolExecutionContext {
        ToolExecutionContext(modelContext: c, flags: f ?? flags())
    }

    private func tool(_ name: String, _ f: CoachFeatureFlags? = nil) throws -> AnyCoachTool {
        try XCTUnwrap(ToolRegistry(flags: f ?? flags()).tool(named: name))
    }

    private func parse(_ result: ToolResult) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(result.jsonString.utf8)) as? [String: Any])
    }

    // MARK: Tasks

    func testTaskCreateListCompleteDeleteFlow() async throws {
        let c = try TestSupport.makeContext()
        // create via platform tool
        _ = try await tool("create_task").run(Data(#"{"title":"Ship oravilles packaging","group":"Oravilles","due_date":null}"#.utf8), ctx(c))
        let listed = try parse(try await tool("list_tasks").run(Data(#"{"status":null,"group":null,"due_within_days":null}"#.utf8), ctx(c)))
        let tasks = try XCTUnwrap(listed["tasks"] as? [[String: Any]])
        XCTAssertEqual(tasks.count, 1)
        let id = try XCTUnwrap(tasks.first?["id"] as? String)

        // complete it
        _ = try await tool("complete_task").run(Data(#"{"task_id":"\#(id)","done":true}"#.utf8), ctx(c))
        let item = try XCTUnwrap((try c.fetch(FetchDescriptor<TaskItem>())).first)
        XCTAssertEqual(item.status, .done)

        // delete → confirmation, not immediate
        let context = ctx(c)
        let del = try parse(try await tool("delete_task").run(Data(#"{"task_id":"\#(id)"}"#.utf8), context))
        XCTAssertEqual(del["needs_confirmation"] as? Bool, true)
        XCTAssertEqual(context.pendingActions.first?.kind, .deleteEntity)
        XCTAssertEqual((try c.fetch(FetchDescriptor<TaskItem>())).count, 1)
        _ = PendingActionExecutor.execute(try XCTUnwrap(context.pendingActions.first), context: c)
        XCTAssertTrue((try c.fetch(FetchDescriptor<TaskItem>())).isEmpty)
    }

    // MARK: Notes

    func testNoteCreateAppendSearchAndDelete() async throws {
        let c = try TestSupport.makeContext()
        let created = try parse(try await tool("create_note").run(Data(#"{"title":"Project plan","body":"Kickoff Monday"}"#.utf8), ctx(c)))
        let noteId = try XCTUnwrap(created["note_id"] as? String)

        _ = try await tool("append_to_note").run(Data(#"{"note_id":"\#(noteId)","content":"Call the supplier about samples","kind":"todo"}"#.utf8), ctx(c))

        // content search finds the appended body text, not just the title
        let found = try parse(try await tool("list_notes").run(Data(#"{"query":"supplier","tag":null,"limit":null}"#.utf8), ctx(c)))
        XCTAssertEqual(found["count"] as? Int, 1)

        // tag it
        _ = try await tool("set_note_tags").run(Data(#"{"note_id":"\#(noteId)","tags":["Work","work","oravilles"]}"#.utf8), ctx(c))
        let note = try XCTUnwrap((try c.fetch(FetchDescriptor<Note>())).first)
        XCTAssertEqual(Set(note.tags), Set(["work", "oravilles"]))  // deduped + lowercased

        // delete → confirm + execute
        let context = ctx(c)
        _ = try await tool("delete_note").run(Data(#"{"note_id":"\#(noteId)"}"#.utf8), context)
        _ = PendingActionExecutor.execute(try XCTUnwrap(context.pendingActions.first), context: c)
        XCTAssertTrue((try c.fetch(FetchDescriptor<Note>())).isEmpty)
    }

    // MARK: Protocol

    func testCreateMedicationAndLogDose() async throws {
        let c = try TestSupport.makeContext()
        let created = try parse(try await tool("create_or_update_medication").run(Data(#"{"medication_id":null,"name":"Vitamin D","dose":"2000 IU","category":"vitamin","timing":"AM","instructions":null,"is_active":null}"#.utf8), ctx(c)))
        let medId = try XCTUnwrap(created["medication_id"] as? String)
        _ = try await tool("log_medication_taken").run(Data(#"{"medication_id":"\#(medId)","status":"taken"}"#.utf8), ctx(c))
        XCTAssertEqual((try c.fetch(FetchDescriptor<MedicationLog>())).count, 1)
    }

    // MARK: Daily life

    func testLogMoodClampsScale() async throws {
        let c = try TestSupport.makeContext()
        _ = try await tool("log_mood").run(Data(#"{"mood":9,"energy":0,"anxiety":null,"focus":null,"notes":null,"tags":null}"#.utf8), ctx(c))
        let entry = try XCTUnwrap((try c.fetch(FetchDescriptor<MoodEntry>())).first)
        XCTAssertEqual(entry.mood, 5)
        XCTAssertEqual(entry.energy, 1)
    }

    // MARK: Profile

    func testSetProfileValidatesRanges() async throws {
        let c = try TestSupport.makeContext()
        let result = try parse(try await tool("set_profile").run(Data(#"{"name":"Rey","age":900,"sex":null,"height_cm":180,"weight_kg":75,"reason":"enable BMI"}"#.utf8), ctx(c)))
        let updated = try XCTUnwrap(result["updated"] as? [String])
        XCTAssertTrue(updated.contains("name"))
        XCTAssertTrue(updated.contains("height_cm"))
        XCTAssertFalse(updated.contains("age"))  // 900 rejected
    }

    // MARK: Navigation

    func testNavigateToQueuesRoute() async throws {
        let c = try TestSupport.makeContext()
        CoachNavigation.shared.requestedRoute = nil
        CoachNavigation.shared.requestedTab = nil
        _ = try await tool("navigate_to").run(Data(#"{"destination":"notes","reason":"show notes"}"#.utf8), ctx(c))
        XCTAssertEqual(CoachNavigation.shared.requestedRoute, .notesList)
        CoachNavigation.shared.requestedRoute = nil
    }

    // MARK: Spec records

    func testSpecRecordCreateAndList() async throws {
        let c = try TestSupport.makeContext()
        let subAppID = SpecSubAppCatalog.moodCheckInSpec.id
        let entity = try XCTUnwrap(SpecSubAppCatalog.moodCheckInSpec.entities.first?.name)

        // Sanity: empty fetch/list should not crash.
        let empty = try parse(try await tool("list_spec_records").run(
            Data(#"{"subapp_id":"\#(subAppID)","entity":"\#(entity)"}"#.utf8), ctx(c)))
        XCTAssertEqual(empty["count"] as? Int, 0)

        // Provide all required fields (mood rating + when date).
        let created = try parse(try await tool("create_spec_record").run(
            Data(#"{"subapp_id":"\#(subAppID)","entity":"\#(entity)","record_id":null,"values":{"mood":4,"when":"2026-06-20"}}"#.utf8), ctx(c)))
        XCTAssertEqual(created["ok"] as? Bool, true)

        let listed = try parse(try await tool("list_spec_records").run(
            Data(#"{"subapp_id":"\#(subAppID)","entity":"\#(entity)"}"#.utf8), ctx(c)))
        XCTAssertEqual(listed["count"] as? Int, 1)
    }

    // MARK: Gating

    func testBrainReadToolsAlwaysPresentWritesGated() {
        let readOnly = flags(write: false, platform: false)
        let readNames = Set(ToolRegistry(flags: readOnly).toolSpecs.compactMap { $0["name"] as? String })
        XCTAssertTrue(readNames.contains("list_tasks"))     // reads always on
        XCTAssertTrue(readNames.contains("list_notes"))
        XCTAssertFalse(readNames.contains("update_task"))   // writes gated
        XCTAssertFalse(readNames.contains("delete_note"))

        let full = Set(ToolRegistry(flags: flags()).toolSpecs.compactMap { $0["name"] as? String })
        XCTAssertTrue(full.contains("update_task"))
        XCTAssertTrue(full.contains("create_or_update_medication"))
        XCTAssertTrue(full.contains("navigate_to"))
        XCTAssertTrue(full.contains("create_spec_record"))
    }
}
