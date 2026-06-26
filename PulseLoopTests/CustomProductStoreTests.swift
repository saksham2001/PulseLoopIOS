import XCTest
import SwiftData
@testable import PulseLoop

// MARK: - CustomProductStore persistence/de-dupe tests (Tracker B2)
@MainActor
final class CustomProductStoreTests: XCTestCase {

    func testUpsertCreatesThenDeDupesByName() throws {
        let c = try TestSupport.makeContext()
        let (_, created1) = CustomProductStore.upsert(
            name: "Tongkat Ali", aliases: ["longjack"], category: "supplement",
            defaultDose: "400 mg", source: "AI Research", isAIGenerated: true, in: c)
        XCTAssertTrue(created1)

        // Same name (different case) updates the existing row instead of duplicating.
        let (_, created2) = CustomProductStore.upsert(
            name: "tongkat ali", aliases: ["eurycoma"], category: "supplement",
            defaultDose: "600 mg", source: "AI Research", isAIGenerated: true, in: c)
        XCTAssertFalse(created2, "Re-discovering the same product must not create a duplicate")

        let all = CustomProductStore.all(c)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.defaultDose, "600 mg", "fields refresh on re-upsert")
        XCTAssertTrue(all.first!.aliases.contains("longjack"))
        XCTAssertTrue(all.first!.aliases.contains("eurycoma"), "aliases merge")
    }

    func testFindAndFuzzyMatchHitPersistedEntries() throws {
        let c = try TestSupport.makeContext()
        CustomProductStore.upsert(name: "BPC-157", aliases: ["bpc157", "body protection compound"],
                                  category: "peptide", in: c)

        XCTAssertNotNil(CustomProductStore.find("BPC-157", in: c))
        XCTAssertNotNil(CustomProductStore.find("bpc157", in: c), "alias match")
        XCTAssertFalse(CustomProductStore.fuzzyMatch("protection compound", in: c).isEmpty)
        XCTAssertNil(CustomProductStore.find("creatine", in: c))
    }

    func testToSupplementInfoRoundTrip() throws {
        let c = try TestSupport.makeContext()
        let (p, _) = CustomProductStore.upsert(
            name: "Magnesium Glycinate", category: "supplement", defaultDose: "400 mg",
            iconSystemName: "drop.fill", timing: "PM", benefit: "Sleep + relaxation", in: c)
        let info = CustomProductStore.toSupplementInfo(p)
        XCTAssertEqual(info.name, "Magnesium Glycinate")
        XCTAssertEqual(info.emoji, "drop.fill")
        XCTAssertEqual(info.timing, "PM")
        XCTAssertEqual(info.defaultDose, "400 mg")
    }

    func testCleanupDuplicatesMergesByName() throws {
        let c = try TestSupport.makeContext()
        // Insert genuine duplicates directly (bypassing upsert's de-dupe) to
        // simulate rows left by an older build.
        let older = CustomProductInfo(name: "Creatine", aliases: ["mono"], category: "supplement")
        older.createdAt = Date(timeIntervalSince1970: 1_000)
        let newer = CustomProductInfo(name: "creatine", aliases: ["monohydrate"], category: "supplement")
        newer.createdAt = Date(timeIntervalSince1970: 2_000)
        c.insert(older)
        c.insert(newer)
        try c.save()
        XCTAssertEqual(CustomProductStore.all(c).count, 2)

        let removed = CustomProductStore.cleanupDuplicates(in: c)
        XCTAssertEqual(removed, 1)

        let remaining = CustomProductStore.all(c)
        XCTAssertEqual(remaining.count, 1)
        // Keeps the newest and merges aliases from the removed row.
        XCTAssertEqual(remaining.first?.name, "creatine")
        XCTAssertTrue(remaining.first!.aliases.contains("mono"))
        XCTAssertTrue(remaining.first!.aliases.contains("monohydrate"))
    }

    func testCleanupDuplicatesNoopWhenUnique() throws {
        let c = try TestSupport.makeContext()
        CustomProductStore.upsert(name: "Zinc", in: c)
        CustomProductStore.upsert(name: "Vitamin D3", in: c)
        XCTAssertEqual(CustomProductStore.cleanupDuplicates(in: c), 0)
        XCTAssertEqual(CustomProductStore.all(c).count, 2)
    }
}
