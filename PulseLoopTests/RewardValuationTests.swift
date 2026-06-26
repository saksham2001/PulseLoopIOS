import Foundation
import XCTest
import SwiftData
@testable import PulseLoop

// MARK: - Points / rewards valuation tests (Travel+ T9)
//
// Pure valuation math (cpp conversion, earn, effective cost, ranking) + the points
// valuation provider (request build / parse / isConfigured + default-cpp fallback) +
// the rewards coach tools, all offline with stubs and an in-memory store.
@MainActor
final class RewardValuationTests: XCTestCase {

    // MARK: Pure valuation math

    func testFormatPoints() {
        XCTAssertEqual(PointsValuator.formatPoints(350), "350")
        XCTAssertEqual(PointsValuator.formatPoints(35200), "35.2k")
        XCTAssertEqual(PointsValuator.formatPoints(60000), "60k")
        XCTAssertEqual(PointsValuator.formatPoints(1_000_000), "1M")
    }

    func testDefaultCPPKnownAndFallback() {
        XCTAssertEqual(DefaultPointValues.cpp(for: "Chase UR"), 1.5)
        XCTAssertEqual(DefaultPointValues.cpp(for: "Amex MR"), 1.6)
        XCTAssertEqual(DefaultPointValues.cpp(for: "United miles"), 1.35)
        XCTAssertEqual(DefaultPointValues.cpp(for: "Totally Unknown Program"), 1.0)
    }

    func testSpendCategoryMapping() {
        XCTAssertEqual(SpendCategory.from(.flight), .travel)
        XCTAssertEqual(SpendCategory.from(.lodging), .travel)
        XCTAssertEqual(SpendCategory.from(.transport), .travel)
        XCTAssertEqual(SpendCategory.from(.restaurant), .dining)
        XCTAssertEqual(SpendCategory.from(.activity), .other)
    }

    func testBestEarnCardPicksHighestValuePerDollar() {
        // Card A: 3x travel @ 1.5cpp = 4.5 c/$. Card B: 2x travel @ 2.0cpp = 4.0 c/$.
        let a = RewardCard(name: "Sapphire", currency: "Chase UR", centsPerPoint: 1.5, earnTravel: 3)
        let b = RewardCard(name: "Venture", currency: "Capital One", centsPerPoint: 2.0, earnTravel: 2)
        let best = PointsValuator.bestEarnCard([a, b], category: .travel)
        XCTAssertEqual(best?.name, "Sapphire")
    }

    func testEvaluateCashEarnReducesEffectiveCost() {
        let card = RewardCard(name: "Sapphire", currency: "Chase UR", centsPerPoint: 1.5, earnTravel: 3)
        let v = PointsValuator.evaluate(cashPrice: 400, currency: "USD", category: .travel, cards: [card])
        // earn: 400 * 3 pts = 1200 pts * 1.5c = 1800c = $18 back.
        XCTAssertEqual(v.earnedValue, 18, accuracy: 0.001)
        XCTAssertEqual(v.effectiveCashCost ?? -1, 382, accuracy: 0.001)
        XCTAssertEqual(v.bestEffectiveCost ?? -1, 382, accuracy: 0.001)
        XCTAssertEqual(v.earnCardName, "Sapphire")
        XCTAssertTrue(v.isEstimate)
        XCTAssertTrue(v.recommendation.contains("Sapphire"))
    }

    func testEvaluateAwardBeatsCashWhenCheaper() {
        let card = RewardCard(name: "United Club", currency: "United miles", centsPerPoint: 1.35, earnTravel: 2)
        // Cash $900 (earn 900*2*1.35c=$24.30 back → effective $875.70).
        // Award: 30k miles + $56 fees → 30000*1.35c=$405 + $56 = $461 → award wins.
        let award = AwardPrice(points: 30000, fees: 56, currency: "United miles")
        let v = PointsValuator.evaluate(cashPrice: 900, currency: "USD", category: .travel, cards: [card], award: award)
        XCTAssertEqual(v.awardCost ?? -1, 461, accuracy: 0.001)
        XCTAssertEqual(v.bestEffectiveCost ?? -1, 461, accuracy: 0.001)
        XCTAssertTrue(v.recommendation.contains("pts"))
        XCTAssertTrue(v.recommendation.contains("United Club"))
    }

    func testEvaluateNoCardsStillReportsCash() {
        let v = PointsValuator.evaluate(cashPrice: 250, category: .other, cards: [])
        XCTAssertEqual(v.earnedValue, 0)
        XCTAssertEqual(v.effectiveCashCost, 250)
        XCTAssertEqual(v.bestEffectiveCost, 250)
        XCTAssertNil(v.earnCardName)
    }

    func testCardLookupByCurrency() {
        let cards = [
            RewardCard(name: "CSR", currency: "Chase UR"),
            RewardCard(name: "United", currency: "United miles"),
        ]
        XCTAssertEqual(PointsValuator.card(for: "United miles", in: cards)?.name, "United")
        XCTAssertEqual(PointsValuator.card(for: "chase ur", in: cards)?.name, "CSR")
        XCTAssertNil(PointsValuator.card(for: "Delta SkyMiles", in: cards))
    }

    // MARK: Provider — request / parse / gating

    final class StubTransport: HTTPTransport, @unchecked Sendable {
        var body: Any
        var statusCode = 200
        private(set) var requests: [URLRequest] = []
        init(_ body: Any) { self.body = body }
        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            requests.append(request)
            let data = try JSONSerialization.data(withJSONObject: body)
            let http = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
            return (data, http)
        }
    }

    func testProviderFallsBackToDefaultWhenUnconfigured() async throws {
        let provider = LivePointsValuationProvider(
            transport: StubTransport(["cents_per_point": 9.9]),
            baseURL: "REPLACE_ME", apiKey: "REPLACE_ME"
        )
        let v = try await provider.valuation(for: "Chase UR")
        XCTAssertFalse(v.isLive)
        XCTAssertEqual(v.centsPerPoint, 1.5)  // default, not the stub's 9.9
    }

    func testProviderUsesLiveValueWhenConfigured() async throws {
        let transport = StubTransport(["cents_per_point": 2.1])
        let provider = LivePointsValuationProvider(
            transport: transport, baseURL: "https://points.example.com", apiKey: "realkey"
        )
        let v = try await provider.valuation(for: "Amex MR")
        XCTAssertTrue(v.isLive)
        XCTAssertEqual(v.centsPerPoint, 2.1)
        let req = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer realkey")
        XCTAssertTrue(req.url?.absoluteString.contains("currency=Amex%20MR") ?? false)
    }

    func testProviderParseCPPVariants() throws {
        let provider = LivePointsValuationProvider(baseURL: "https://x", apiKey: "k")
        XCTAssertEqual(try provider.parseCPP(Data(#"{"cents_per_point":1.7}"#.utf8)), 1.7)
        XCTAssertEqual(try provider.parseCPP(Data(#"{"cents_per_point":2}"#.utf8)), 2.0)
        XCTAssertEqual(try provider.parseCPP(Data(#"{"cents_per_point":"1.4"}"#.utf8)), 1.4)
        XCTAssertThrowsError(try provider.parseCPP(Data(#"{"nope":1}"#.utf8)))
    }

    func testProviderNetworkErrorFallsBack() async throws {
        let transport = StubTransport(["cents_per_point": 5.0]); transport.statusCode = 500
        let provider = LivePointsValuationProvider(
            transport: transport, baseURL: "https://points.example.com", apiKey: "realkey")
        let v = try await provider.valuation(for: "Chase UR")
        XCTAssertFalse(v.isLive)
        XCTAssertEqual(v.centsPerPoint, 1.5)  // default fallback after 500
    }

    // MARK: Coach tools

    private func writeFlags() -> CoachFeatureFlags {
        var s = CoachSettings.default
        s.enableWriteTools = true
        return CoachFeatureFlags(settings: s, hasAPIKey: true)
    }
    private func ctx(_ c: ModelContext) -> ToolExecutionContext {
        ToolExecutionContext(modelContext: c, flags: writeFlags())
    }
    private func tool(_ name: String) throws -> AnyCoachTool {
        try XCTUnwrap((TravelTools.readTools + TravelTools.writeTools).first { $0.name == name }, "missing \(name)")
    }
    private func parse(_ r: ToolResult) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(r.jsonString.utf8)) as? [String: Any])
    }

    func testAddAndListRewardCard() async throws {
        let c = try TestSupport.makeContext()
        let added = try parse(try await tool("add_reward_card").run(
            Data(#"{"name":"Chase Sapphire Reserve","currency":"Chase UR","points_balance":85000,"cents_per_point":1.5,"earn_travel":3,"earn_dining":3,"earn_other":1}"#.utf8),
            ctx(c)))
        XCTAssertEqual(added["ok"] as? Bool, true)

        let stored = try c.fetch(FetchDescriptor<RewardCard>())
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.pointsBalance, 85000)
        XCTAssertEqual(stored.first?.earnTravel, 3)

        let listed = try parse(try await tool("list_reward_cards").run(Data("{}".utf8), ctx(c)))
        XCTAssertEqual(listed["count"] as? Int, 1)
    }

    func testValueWithPointsRanksOptions() async throws {
        let c = try TestSupport.makeContext()
        _ = try await tool("add_reward_card").run(
            Data(#"{"name":"United Club","currency":"United miles","points_balance":50000,"cents_per_point":1.35,"earn_travel":2,"earn_dining":1,"earn_other":1}"#.utf8),
            ctx(c))

        // Two flights: one cheaper cash, one with an attractive award.
        let out = try parse(try await tool("value_with_points").run(
            Data("""
            {"options":[
              {"title":"Cash fare","kind":"flight","cash_price":900,"currency":"USD","award_points":null,"award_fees":null,"award_currency":null},
              {"title":"Award fare","kind":"flight","cash_price":900,"currency":"USD","award_points":30000,"award_fees":56,"award_currency":"United miles"}
            ]}
            """.utf8),
            ctx(c)))
        XCTAssertEqual(out["ok"] as? Bool, true)
        let ranked = try XCTUnwrap(out["ranked_options"] as? [[String: Any]])
        XCTAssertEqual(ranked.count, 2)
        // Award option ($461) should outrank the cash effective cost (~$875.70).
        XCTAssertEqual(ranked.first?["title"] as? String, "Award fare")
        XCTAssertEqual(ranked.first?["best_effective_cost"] as? Double ?? -1, 461, accuracy: 0.5)
        XCTAssertEqual(ranked.first?["is_estimate"] as? Bool, true)
    }

    func testValueWithPointsWithNoCardsUsesCash() async throws {
        let c = try TestSupport.makeContext()
        let out = try parse(try await tool("value_with_points").run(
            Data("""
            {"options":[{"title":"Hotel","kind":"lodging","cash_price":300,"currency":"USD","award_points":null,"award_fees":null,"award_currency":null}]}
            """.utf8),
            ctx(c)))
        let ranked = try XCTUnwrap(out["ranked_options"] as? [[String: Any]])
        XCTAssertEqual(ranked.first?["best_effective_cost"] as? Double, 300)
    }
}
