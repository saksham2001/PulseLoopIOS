import XCTest
@testable import PulseLoop

@MainActor
final class MealEstimatorTests: XCTestCase {

    func testDecodesCleanJSON() throws {
        let raw = """
        {"name":"Chicken Bowl","icon_system_name":"fork.knife","calories":620,"protein_g":45,"carbs_g":55,"fat_g":18,"note":"High protein"}
        """
        let est = try XCTUnwrap(MealEstimator.decode(raw, fallbackName: "x"))
        XCTAssertEqual(est.name, "Chicken Bowl")
        XCTAssertEqual(est.calories, 620)
        XCTAssertEqual(est.proteinG, 45)
        XCTAssertEqual(est.emoji, "fork.knife")
        XCTAssertTrue(est.isAIGenerated)
        XCTAssertTrue(est.macroSummary.contains("620 kcal"))
    }

    func testExtractsJSONFromProse() throws {
        let raw = """
        Here is the estimate:
        ```json
        {"name":"Oatmeal","icon_system_name":"cup.and.saucer.fill","calories":310,"protein_g":10,"carbs_g":50,"fat_g":8,"note":""}
        ```
        Hope that helps!
        """
        let est = try XCTUnwrap(MealEstimator.decode(raw, fallbackName: "x"))
        XCTAssertEqual(est.name, "Oatmeal")
        XCTAssertEqual(est.calories, 310)
    }

    func testRejectsEmojiSymbolFallsBackToForkKnife() throws {
        let raw = """
        {"name":"Salad","icon_system_name":"🥗","calories":200,"protein_g":5,"carbs_g":15,"fat_g":12,"note":""}
        """
        let est = try XCTUnwrap(MealEstimator.decode(raw, fallbackName: "x"))
        XCTAssertEqual(est.emoji, "fork.knife")
    }

    func testUsesFallbackNameWhenMissing() throws {
        let raw = """
        {"calories":150,"protein_g":2,"carbs_g":30,"fat_g":1}
        """
        let est = try XCTUnwrap(MealEstimator.decode(raw, fallbackName: "apple"))
        XCTAssertEqual(est.name, "apple")
    }

    func testReturnsNilWhenNoCalories() {
        XCTAssertNil(MealEstimator.decode("{\"name\":\"x\"}", fallbackName: "x"))
        XCTAssertNil(MealEstimator.decode("not json at all", fallbackName: "x"))
    }

    func testQuickEstimateMatchesKeywordTable() {
        let est = MealEstimator.quickEstimate("chicken and rice")
        XCTAssertNotNil(est)
        XCTAssertEqual(est?.isAIGenerated, false)
        XCTAssertGreaterThan(est?.calories ?? 0, 0)
    }
}
