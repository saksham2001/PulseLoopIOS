import XCTest
@testable import PulseLoop

// MARK: - Product research (AI "Perplexity" tier) parse/normalize tests (Tracker B1)
//
// Exercises ProductResearchService.decode without any network call: extracting JSON
// from noisy model output, category normalization, SF-Symbol sanitization (no emoji),
// and confidence clamping.
@MainActor
final class ProductResearchTests: XCTestCase {

    private let sampleJSON = """
    {
      "name": "Berberine",
      "aliases": ["berberine hcl"],
      "category": "Supplement",
      "default_dose": "500 mg",
      "icon_system_name": "pills.fill",
      "timing": "With food",
      "benefit": "Supports healthy blood sugar.",
      "mechanism": "Activates AMPK.",
      "best_time_reason": "Take with meals to blunt glucose spikes.",
      "interaction_notes": "May interact with metformin.",
      "pros": ["Glucose support", "Lipid support", "Gut effects", "Cheap", "Extra"],
      "cons": ["GI upset"],
      "citations": ["Examine.com", "PubMed"],
      "confidence": 0.82
    }
    """

    func testDecodesCleanJSON() throws {
        let p = try XCTUnwrap(ProductResearchService.decode(sampleJSON, fallbackName: "x"))
        XCTAssertEqual(p.name, "Berberine")
        XCTAssertEqual(p.category, "supplement")          // normalized lowercase
        XCTAssertEqual(p.defaultDose, "500 mg")
        XCTAssertEqual(p.iconSystemName, "pills.fill")
        XCTAssertEqual(p.pros.count, 4, "pros should be capped at 4")
        XCTAssertEqual(p.citations, ["Examine.com", "PubMed"])
        XCTAssertEqual(p.confidence, 0.82, accuracy: 0.0001)
    }

    func testExtractsJSONFromProseAndCodeFence() throws {
        let noisy = "Here is the profile you asked for:\n```json\n\(sampleJSON)\n```\nHope that helps!"
        let p = try XCTUnwrap(ProductResearchService.decode(noisy, fallbackName: "x"))
        XCTAssertEqual(p.name, "Berberine")
    }

    func testRejectsEmojiSymbolAndFallsBackByCategory() throws {
        let json = #"{"name":"Creatine","category":"supplement","icon_system_name":"💊"}"#
        let p = try XCTUnwrap(ProductResearchService.decode(json, fallbackName: "x"))
        XCTAssertEqual(p.iconSystemName, "pills.fill", "emoji must be replaced with an SF Symbol")
    }

    func testUsesFallbackNameWhenMissing() throws {
        let json = #"{"category":"peptide","confidence":2.0}"#
        let p = try XCTUnwrap(ProductResearchService.decode(json, fallbackName: "BPC-157"))
        XCTAssertEqual(p.name, "BPC-157")
        XCTAssertEqual(p.category, "peptide")
        XCTAssertEqual(p.iconSystemName, "syringe.fill")
        XCTAssertEqual(p.timing, "PM", "peptide default timing")
        XCTAssertEqual(p.confidence, 1.0, "confidence clamps to 1.0")
    }

    func testReturnsNilForNonJSON() {
        XCTAssertNil(ProductResearchService.decode("I could not find that product.", fallbackName: "x"))
    }

    func testAsSupplementInfoCarriesDisclaimer() throws {
        let p = try XCTUnwrap(ProductResearchService.decode(sampleJSON, fallbackName: "x"))
        let info = p.asSupplementInfo
        XCTAssertTrue(info.stackNotes.lowercased().contains("verify"))
        XCTAssertEqual(info.name, "Berberine")
    }
}
