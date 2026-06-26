import XCTest
@testable import PulseLoop

/// Verifies the supplement catalog and (re)generates the bundled JSON resource
/// from the in-source data. Run with `PULSELOOP_REGEN_SUPPLEMENTS=1` to rewrite
/// `PulseLoop/Resources/supplements.json` from `inSourceDatabase`.
final class SupplementCatalogTests: XCTestCase {

    func testInSourceDatabaseRoundTripsThroughJSON() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(SupplementKnowledge.inSourceDatabase)
        let decoded = try JSONDecoder().decode([SupplementInfo].self, from: data)
        XCTAssertEqual(decoded.count, SupplementKnowledge.inSourceDatabase.count)
        XCTAssertEqual(decoded.first?.name, SupplementKnowledge.inSourceDatabase.first?.name)
    }

    func testPublicDatabaseIsNonEmpty() {
        XCTAssertFalse(SupplementKnowledge.database.isEmpty)
    }

    /// Generator: prints the bundled JSON (from in-source data) to stdout so it can
    /// be captured and written to `PulseLoop/Resources/supplements.json`.
    func testRegenerateBundledJSON() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(SupplementKnowledge.inSourceDatabase)
        let json = String(data: data, encoding: .utf8) ?? ""
        print("===SUPPLEMENTS_JSON_BEGIN===")
        print(json)
        print("===SUPPLEMENTS_JSON_END===")
    }
}
