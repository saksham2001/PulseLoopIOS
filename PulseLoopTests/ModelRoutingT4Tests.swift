import XCTest
@testable import PulseLoop

/// T4 — model capability registry, feedback-weighted ranking, smarter routing
/// (auto/override/anchor), and the catalog refresh parser.
final class ModelRoutingT4Tests: XCTestCase {

    private let keys = [
        AgentRouter.autoModelKey,
        AIModel.smart.storageKey,
        AIModel.vision.storageKey,
        "agentRole.strategist",
        "agentRole.researcher",
    ]

    override func setUp() {
        super.setUp()
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
    }
    override func tearDown() {
        keys.forEach { UserDefaults.standard.removeObject(forKey: $0) }
        super.tearDown()
    }

    // MARK: Registry

    func testGeneralistCandidatesAreToolCapableAndJSONReliable() {
        let candidates = ModelRegistry.candidates(for: .generalist)
        XCTAssertFalse(candidates.isEmpty)
        XCTAssertTrue(candidates.allSatisfy { $0.supportsTools && $0.jsonReliable })
        // Known JSON-unreliable slugs must be excluded from the generalist pool.
        XCTAssertFalse(candidates.contains { AIModel.jsonUnreliableSlugs.contains($0.slug) })
    }

    func testVisionCandidatesAreMultimodal() {
        XCTAssertTrue(ModelRegistry.candidates(for: .vision).allSatisfy { $0.supportsVision })
    }

    func testDisplayNameFallsBackToSlugComponent() {
        XCTAssertEqual(ModelRegistry.displayName(for: "openai/gpt-4o-mini"), "GPT-4o mini")
        XCTAssertEqual(ModelRegistry.displayName(for: "vendor/unknown-model"), "unknown-model")
    }

    // MARK: Ranking (pure)

    func testRankingPrefersHigherPriorWithNoSignal() {
        let caps = [
            ModelCapability(slug: "weak", displayName: "Weak", supportsTools: true, supportsVision: false, jsonReliable: true, quality: 50, costRank: 10),
            ModelCapability(slug: "strong", displayName: "Strong", supportsTools: true, supportsVision: false, jsonReliable: true, quality: 95, costRank: 10),
        ]
        XCTAssertEqual(ModelRanking.best(candidates: caps, stats: [:]), "strong")
    }

    func testGoodFeedbackOverridesWeakerPrior() {
        let caps = [
            ModelCapability(slug: "weak", displayName: "Weak", supportsTools: true, supportsVision: false, jsonReliable: true, quality: 55, costRank: 10),
            ModelCapability(slug: "strong", displayName: "Strong", supportsTools: true, supportsVision: false, jsonReliable: true, quality: 80, costRank: 10),
        ]
        // "weak" earns lots of thumbs-up; "strong" gets thumbs-down + recoveries.
        var weakStats = ModelOutcomeStats(model: "weak"); weakStats.upVotes = 20; weakStats.turns = 20
        var strongStats = ModelOutcomeStats(model: "strong"); strongStats.downVotes = 10; strongStats.turns = 10; strongStats.recoveredTurns = 8; strongStats.erroredTurns = 4
        let best = ModelRanking.best(candidates: caps, stats: ["weak": weakStats, "strong": strongStats])
        XCTAssertEqual(best, "weak", "Strong, consistent positive feedback should win over a higher static prior.")
    }

    func testRankingIsDeterministic() {
        let caps = ModelRegistry.candidates(for: .strategist)
        let a = ModelRanking.rank(candidates: caps, stats: [:])
        let b = ModelRanking.rank(candidates: caps, stats: [:])
        XCTAssertEqual(a, b)
    }

    func testHasSignalFlag() {
        let caps = [ModelCapability(slug: "m", displayName: "M", supportsTools: true, supportsVision: false, jsonReliable: true, quality: 70, costRank: 10)]
        XCTAssertFalse(ModelRanking.rank(candidates: caps, stats: [:]).first!.hasSignal)
        var s = ModelOutcomeStats(model: "m"); s.turns = 3
        XCTAssertTrue(ModelRanking.rank(candidates: caps, stats: ["m": s]).first!.hasSignal)
    }

    // MARK: Router selection

    func testAutoModeReturnsRegistryCandidate() {
        UserDefaults.standard.set(true, forKey: AgentRouter.autoModelKey)
        let slug = AgentRouter.bestModel(for: .strategist)
        XCTAssertTrue(ModelRegistry.candidates(for: .strategist).map(\.slug).contains(slug))
    }

    func testExplicitOverrideWinsOverAuto() {
        UserDefaults.standard.set("anthropic/claude-opus-4.8", forKey: "agentRole.strategist")
        XCTAssertTrue(AgentRouter.hasExplicitOverride(for: .strategist))
        XCTAssertEqual(AgentRouter.bestModel(for: .strategist), "anthropic/claude-opus-4.8")
    }

    func testGeneralistNeverPicksUnreliableJSONModel() {
        UserDefaults.standard.set(true, forKey: AgentRouter.autoModelKey)
        let slug = AgentRouter.bestModel(for: .generalist)
        XCTAssertFalse(AIModel.jsonUnreliableSlugs.contains(slug))
    }

    func testAutoDisabledFallsBackToRoleDefault() {
        UserDefaults.standard.set(false, forKey: AgentRouter.autoModelKey)
        XCTAssertEqual(AgentRouter.bestModel(for: .researcher), AgentRole.researcher.modelSlug)
    }

    func testRoutingRationaleIsHumanReadable() {
        let r = AgentRouter.routingRationale(role: .strategist, slug: "nvidia/nemotron-3-super-120b-a12b", autoPicked: true)
        XCTAssertTrue(r.contains("Reasoning task"))
        XCTAssertTrue(r.contains("Nemotron 3 Super"))
    }

    // MARK: Catalog parser

    func testCatalogParserReadsCapabilities() {
        let body: [String: Any] = [
            "data": [[
                "id": "vendor/new-model",
                "name": "New Model",
                "architecture": ["input_modalities": ["text", "image"]],
                "supported_parameters": ["tools", "temperature"],
            ]]
        ]
        let data = try! JSONSerialization.data(withJSONObject: body)
        let caps = OpenRouterModelCatalogProvider.parse(data)
        let cap = caps.first { $0.slug == "vendor/new-model" }
        XCTAssertNotNil(cap)
        XCTAssertTrue(cap!.supportsTools)
        XCTAssertTrue(cap!.supportsVision)
    }

    func testCatalogParserIgnoresGarbage() {
        XCTAssertTrue(OpenRouterModelCatalogProvider.parse(Data("nope".utf8)).isEmpty)
    }

    func testRegistryUpdateMergesWithoutLosingBundled() {
        let before = ModelRegistry.all.count
        ModelRegistry.update(with: [
            ModelCapability(slug: "vendor/brand-new", displayName: "Brand New", supportsTools: true, supportsVision: false, jsonReliable: true, quality: 80, costRank: 30)
        ])
        XCTAssertNotNil(ModelRegistry.capability(for: "vendor/brand-new"))
        XCTAssertNotNil(ModelRegistry.capability(for: "openai/gpt-4o-mini"), "Bundled entries must survive a merge.")
        XCTAssertGreaterThan(ModelRegistry.all.count, before - 1)
        // Empty update is a no-op.
        let after = ModelRegistry.all.count
        ModelRegistry.update(with: [])
        XCTAssertEqual(ModelRegistry.all.count, after)
    }
}
