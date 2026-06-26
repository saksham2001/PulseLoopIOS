import XCTest
@testable import PulseLoop

/// Multi-agent router loop tests: roster presence (T0) + pure routing logic (T1) +
/// reasoning-token stripping for specialists (T3).
final class AgentRouterTests: XCTestCase {

    // Routing reads UserDefaults; isolate each test from prior state.
    private func clearRoutingDefaults() {
        let d = UserDefaults.standard
        d.removeObject(forKey: AgentRouter.routingEnabledKey)
        d.removeObject(forKey: "agentRole.strategist")
        d.removeObject(forKey: "agentRole.researcher")
    }

    override func setUp() {
        super.setUp()
        clearRoutingDefaults()
    }

    override func tearDown() {
        clearRoutingDefaults()
        super.tearDown()
    }

    // MARK: - T0 Roster

    func testSpecialistSlugsArePresentAndToolCapable() {
        let smartSlugs = AIModel.smart.options.map(\.slug)
        XCTAssertTrue(smartSlugs.contains(AgentRouter.strategistDefault),
                      "Nemotron must be a selectable smart-tier option")
        XCTAssertTrue(smartSlugs.contains(AgentRouter.researcherDefault),
                      "MiniMax must be a selectable smart-tier option")

        // Specialists must support tool calling (the agent loop depends on it).
        XCTAssertFalse(AIModel.toolIncompatibleSlugs.contains(AgentRouter.strategistDefault))
        XCTAssertFalse(AIModel.toolIncompatibleSlugs.contains(AgentRouter.researcherDefault))

        // The reliability anchor must remain the smart default.
        XCTAssertEqual(AIModel.smart.defaultSlug, "openai/gpt-4o-mini")
    }

    // MARK: - T1 Routing

    func testPhotoAlwaysRoutesToVision() {
        XCTAssertEqual(AgentRouter.route(userText: "what is this?", hasImage: true), .vision)
        // Even with reasoning keywords, a photo forces vision.
        XCTAssertEqual(AgentRouter.route(userText: "analyze this strategy step by step", hasImage: true), .vision)
    }

    func testReasoningPromptsRouteToStrategist() {
        let prompts = [
            "Plan a 3-day strategy to launch my product",
            "Compare the pros and cons of these two options",
            "Help me think through why this keeps failing",
            "Break down the trade-offs and decide between A and B",
        ]
        for p in prompts {
            XCTAssertEqual(AgentRouter.route(userText: p, hasImage: false), .strategist, "\(p)")
        }
    }

    func testResearchPromptsRouteToResearcher() {
        let prompts = [
            "What's the latest news on the merger?",
            "Find the cheapest flights to Tokyo",
            "Look up the current price of gold",
            "Show me the best reviews for this hotel",
        ]
        for p in prompts {
            XCTAssertEqual(AgentRouter.route(userText: p, hasImage: false), .researcher, "\(p)")
        }
    }

    func testSupplementPeptideLongevityRouteToResearcher() {
        // These are core health-app questions that must get a grounded, looked-up
        // answer (not a guess or refusal) — route them to the Researcher.
        let prompts = [
            "I want to lose weight, what peptides should I take? I also want to live longer",
            "What supplements should I take for sleep?",
            "Is it safe to take creatine and what dose?",
            "Best nootropic stack for focus",
        ]
        for p in prompts {
            XCTAssertEqual(AgentRouter.route(userText: p, hasImage: false), .researcher, "\(p)")
        }
    }

    func testAmbiguousPromptsRouteToGeneralist() {
        let prompts = [
            "Hi there",
            "Add eggs to my grocery list",
            "Thanks!",
            "Log my run",
        ]
        for p in prompts {
            XCTAssertEqual(AgentRouter.route(userText: p, hasImage: false), .generalist, "\(p)")
        }
    }

    func testEmptyTextRoutesToGeneralist() {
        XCTAssertEqual(AgentRouter.route(userText: "", hasImage: false), .generalist)
        XCTAssertEqual(AgentRouter.route(userText: "   \n ", hasImage: false), .generalist)
    }

    func testLongMultiPartAskLeansStrategist() {
        let long = "I want to figure out the right way to structure my week; " +
            "what should I focus on first; how do I balance fitness and work; " +
            "and what habits actually stick over the long run for someone busy"
        XCTAssertEqual(AgentRouter.route(userText: long, hasImage: false), .strategist)
    }

    func testRoutingOffSendsEverythingToGeneralist() {
        UserDefaults.standard.set(false, forKey: AgentRouter.routingEnabledKey)
        XCTAssertEqual(AgentRouter.route(userText: "Plan a strategy", hasImage: false), .generalist)
        XCTAssertEqual(AgentRouter.route(userText: "latest news", hasImage: false), .generalist)
        // Photo still forces vision regardless of the toggle.
        XCTAssertEqual(AgentRouter.route(userText: "x", hasImage: true), .vision)
    }

    func testRoleModelSlugDefaults() {
        UserDefaults.standard.removeObject(forKey: AIModel.smart.storageKey)
        XCTAssertEqual(AgentRole.strategist.modelSlug, AgentRouter.strategistDefault)
        XCTAssertEqual(AgentRole.researcher.modelSlug, AgentRouter.researcherDefault)
        XCTAssertEqual(AgentRole.generalist.modelSlug, AIModel.smart.toolCapableResolvedSlug)
    }

    func testGeneralistCoercesUnreliableSmartSlugToAnchor() {
        // A user who picked Gemini Flash for the smart tier must still get a
        // JSON-reliable model on the generalist route (Gemini loops on
        // "I'll fix the JSON" apologies and breaks the structured-output contract).
        UserDefaults.standard.set("google/gemini-2.5-flash", forKey: AIModel.smart.storageKey)
        XCTAssertTrue(AIModel.jsonUnreliableSlugs.contains("google/gemini-2.5-flash"))
        XCTAssertEqual(AgentRole.generalist.modelSlug, AIModel.jsonReliableAnchor)
        UserDefaults.standard.removeObject(forKey: AIModel.smart.storageKey)
    }

    func testReliableSmartSlugIsHonoredOnGeneralist() {
        // A reliable user choice is respected (not coerced).
        UserDefaults.standard.set("anthropic/claude-sonnet-4.6", forKey: AIModel.smart.storageKey)
        XCTAssertEqual(AgentRole.generalist.modelSlug, "anthropic/claude-sonnet-4.6")
        UserDefaults.standard.removeObject(forKey: AIModel.smart.storageKey)
    }

    func testRolePerKeyOverride() {
        UserDefaults.standard.set("custom/model-x", forKey: "agentRole.strategist")
        XCTAssertEqual(AgentRole.strategist.modelSlug, "custom/model-x")
    }

    func testOnlyStrategistNeedsDetailedThinking() {
        XCTAssertTrue(AgentRole.strategist.needsDetailedThinking)
        XCTAssertFalse(AgentRole.generalist.needsDetailedThinking)
        XCTAssertFalse(AgentRole.researcher.needsDetailedThinking)
        XCTAssertFalse(AgentRole.vision.needsDetailedThinking)
    }

    func testNonGeneralistRolesHavePromptHints() {
        XCTAssertFalse(AgentRole.strategist.promptHint.isEmpty)
        XCTAssertFalse(AgentRole.researcher.promptHint.isEmpty)
        XCTAssertTrue(AgentRole.generalist.promptHint.isEmpty)
    }

    // MARK: - T3 Reasoning-token stripping

    func testStripThinkBlock() {
        let raw = "<think>Let me reason about this {nested: true} carefully.</think>{\"x\":1}"
        let stripped = CoachResponseParser.stripReasoningTokens(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(stripped, "{\"x\":1}")
    }

    func testStripMultipleReasoningTags() {
        let raw = "<reasoning>step 1</reasoning> filler <thinking>step 2</thinking>{\"answer\":42}"
        let stripped = CoachResponseParser.stripReasoningTokens(raw)
        XCTAssertFalse(stripped.contains("step 1"))
        XCTAssertFalse(stripped.contains("step 2"))
        XCTAssertTrue(stripped.contains("\"answer\":42"))
    }

    func testStripDanglingCloseTag() {
        let raw = "I am thinking about the problem</think>{\"ok\":true}"
        let stripped = CoachResponseParser.stripReasoningTokens(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(stripped, "{\"ok\":true}")
    }

    func testStripIsIdempotentOnCleanJSON() {
        let clean = "{\"title\":\"hi\"}"
        XCTAssertEqual(CoachResponseParser.stripReasoningTokens(clean), clean)
    }

    func testRoutingEnabledDefaultsOn() {
        // With no stored preference, routing is on by default.
        clearRoutingDefaults()
        XCTAssertTrue(AgentRouter.routingEnabled)
    }

    func testRoutingTogglePersists() {
        UserDefaults.standard.set(false, forKey: AgentRouter.routingEnabledKey)
        XCTAssertFalse(AgentRouter.routingEnabled)
        UserDefaults.standard.set(true, forKey: AgentRouter.routingEnabledKey)
        XCTAssertTrue(AgentRouter.routingEnabled)
    }

    func testShortModelNameMapsKnownSlugs() {
        XCTAssertEqual(AgentRouter.shortModelName("nvidia/nemotron-3-super-120b-a12b"), "Nemotron 3 Super")
        XCTAssertEqual(AgentRouter.shortModelName("minimax/minimax-m2"), "MiniMax M2")
        XCTAssertEqual(AgentRouter.shortModelName("openai/gpt-4o-mini"), "GPT-4o mini")
        // A slug not in the registry falls back to the trailing component.
        XCTAssertEqual(AgentRouter.shortModelName("acme/totally-unknown-model"), "totally-unknown-model")
    }
}
