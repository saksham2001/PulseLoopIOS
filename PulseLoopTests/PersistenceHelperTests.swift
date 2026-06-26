import XCTest
import SwiftData
@testable import PulseLoop

/// Tests for the safe-save persistence helpers (`saveOrLog`/`saveOrThrow`).
@MainActor
final class PersistenceHelperTests: XCTestCase {

    func testSaveOrLogReturnsTrueOnSuccess() throws {
        let context = try TestSupport.makeContext()
        context.insert(TaskItem(title: "Buy milk"))
        XCTAssertTrue(context.saveOrLog("test"))
    }

    func testSaveOrLogReturnsTrueWhenNoChanges() throws {
        let context = try TestSupport.makeContext()
        // No pending changes — should be a no-op success.
        XCTAssertTrue(context.saveOrLog("test"))
    }

    func testSaveOrThrowSucceeds() throws {
        let context = try TestSupport.makeContext()
        context.insert(TaskItem(title: "Walk dog"))
        XCTAssertNoThrow(try context.saveOrThrow("test"))
    }

    func testSaveOrThrowNoOpWhenNoChanges() throws {
        let context = try TestSupport.makeContext()
        XCTAssertNoThrow(try context.saveOrThrow("test"))
    }

    func testPersistenceErrorDescriptionIncludesArea() {
        let err = PersistenceError.saveFailed(area: "coach", underlying: CocoaError(.fileNoSuchFile))
        XCTAssertTrue(err.description.contains("coach"))
    }
}
