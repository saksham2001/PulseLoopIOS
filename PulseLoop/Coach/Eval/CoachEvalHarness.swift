import Foundation

// MARK: - Deterministic eval harness (Life OS T6)
//
// A tiny, network-free harness that checks the two contracts the whole coach
// experience rests on:
//
//   1. ROUTING — a user turn lands on the right specialist role (pure, heuristic
//      `AgentRouter.route`, so same input → same role, no latency, no flakiness).
//   2. SHAPE   — a raw model payload, once parsed and run through the boundary
//      guards (`CoachResponseParser` → `adaptiveShaped`), produces a response with
//      the invariants we render against: clean typography (no em/en dashes), a
//      chart only on an `insight_with_chart`, a non-empty summary, etc.
//
// It's deterministic on purpose: a stubbed "model" is just a string of JSON (or
// prose) per case, so this can run in unit tests AND power an in-app quality
// readout (T6 dashboard) without calling a provider. Add cases as the contract
// grows; each case is a small, readable spec of "given this turn, expect this".

/// One routing expectation: a user utterance should classify to `expectedRole`.
struct RoutingEvalCase {
    let name: String
    let userText: String
    let hasImage: Bool
    let expectedRole: AgentRole

    init(_ name: String, userText: String, hasImage: Bool = false, expectedRole: AgentRole) {
        self.name = name
        self.userText = userText
        self.hasImage = hasImage
        self.expectedRole = expectedRole
    }
}

/// One shape expectation: a raw model output (`rawModelOutput`, JSON or prose),
/// parsed + guarded, must satisfy every `assertions` predicate.
struct ShapeEvalCase {
    let name: String
    let rawModelOutput: String
    let assertions: [ShapeAssertion]

    init(_ name: String, rawModelOutput: String, assertions: [ShapeAssertion]) {
        self.name = name
        self.rawModelOutput = rawModelOutput
        self.assertions = assertions
    }
}

/// A named predicate over a shaped `CoachResponse`. Returning a non-nil string is
/// the failure reason (kept as a value so the dashboard can list what broke).
struct ShapeAssertion {
    let label: String
    let check: (CoachResponse) -> String?

    // MARK: Reusable assertions (the rendered invariants)

    /// No em/en dash (or double-hyphen stand-in) survives in any rendered field.
    static var noEmDash: ShapeAssertion {
        ShapeAssertion(label: "no em/en dash") { r in
            let fields = [r.title, r.summary] + r.bullets + r.followUpChips + r.actionsTaken
                + [r.safetyNote, r.dataQualityNote].compactMap { $0 }
            for f in fields where f.contains("—") || f.contains("–") || f.contains("--") {
                return "found a dash in: \"\(f)\""
            }
            return nil
        }
    }

    /// A chart is only allowed on an explicit `insight_with_chart` reply.
    static var chartMatchesType: ShapeAssertion {
        ShapeAssertion(label: "chart only on insight_with_chart") { r in
            if r.chart != nil && r.responseType != .insightWithChart {
                return "chart present on \(r.responseType.rawValue)"
            }
            return nil
        }
    }

    /// Every reply needs a non-empty summary (the bubble's required body).
    static var hasSummary: ShapeAssertion {
        ShapeAssertion(label: "non-empty summary") { r in
            r.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "summary is empty" : nil
        }
    }

    /// The response decoded to a specific type.
    static func type(_ expected: CoachResponseType) -> ShapeAssertion {
        ShapeAssertion(label: "type == \(expected.rawValue)") { r in
            r.responseType == expected ? nil : "got \(r.responseType.rawValue)"
        }
    }

    /// At least `n` bullets (structure over a wall of text).
    static func minBullets(_ n: Int) -> ShapeAssertion {
        ShapeAssertion(label: "≥ \(n) bullets") { r in
            r.bullets.count >= n ? nil : "got \(r.bullets.count)"
        }
    }
}

/// The result of running one eval case.
struct EvalResult: Identifiable {
    let id = UUID()
    let name: String
    let passed: Bool
    /// Failure reasons (empty when passed).
    let failures: [String]
}

/// Runs the deterministic eval cases. Pure: no I/O, no provider calls.
enum CoachEvalHarness {

    // MARK: Default suites

    /// Routing cases covering the four roles + ambiguous fallback.
    static let routingCases: [RoutingEvalCase] = [
        .init("plain chat → generalist", userText: "remind me to call mom", expectedRole: .generalist),
        .init("planning → strategist", userText: "help me plan and strategize my whole week around training",
              expectedRole: .strategist),
        .init("research → researcher", userText: "research the latest studies on creatine and summarize the sources",
              expectedRole: .researcher),
        .init("image → vision", userText: "what does this nutrition label say?", hasImage: true, expectedRole: .vision),
    ]

    /// Shape cases covering typography, chart-type coupling, and structure.
    static let shapeCases: [ShapeEvalCase] = [
        .init(
            "em dash is stripped",
            rawModelOutput: #"{"response_type":"insight","title":"Sleep — a quick note","summary":"You slept well — nice work.","bullets":["Hydrate first thing — before coffee"]}"#,
            assertions: [.noEmDash, .hasSummary, .type(.insight)]
        ),
        .init(
            "stray chart dropped on plain insight",
            rawModelOutput: #"{"response_type":"insight","title":"Mood","summary":"Sounds like a good day.","chart":{"chart_type":"line","title":"HR","metric":"hr","range":{"start":"Mon","end":"Tue"},"data":[]}}"#,
            assertions: [.chartMatchesType, .hasSummary]
        ),
        .init(
            "chart kept on insight_with_chart",
            rawModelOutput: #"{"response_type":"insight_with_chart","title":"Weight trend","summary":"Down 1.2 lb this week.","chart":{"chart_type":"line","title":"Weight","metric":"steps","range":{"start":"Mon","end":"Tue"},"data":[{"x":"Mon","y":80},{"x":"Tue","y":79.8}]}}"#,
            assertions: [.type(.insightWithChart)]
        ),
        .init(
            "prose fallback still yields a summary",
            rawModelOutput: "Here's a thought: drink more water today.",
            assertions: [.hasSummary]
        ),
        .init(
            "structured insight keeps its bullets",
            rawModelOutput: #"{"response_type":"insight","title":"Plan","summary":"Three steps to start.","bullets":["Warm up","Lift","Cool down"]}"#,
            assertions: [.minBullets(3), .hasSummary, .noEmDash]
        ),
    ]

    // MARK: Runners

    /// Parse + guard a raw model output exactly as the orchestrator's final step
    /// does: try to parse JSON; if that fails, wrap prose; then apply the adaptive
    /// shape guard (which also sanitizes typography).
    static func shaped(_ rawModelOutput: String) -> CoachResponse {
        let parsed = CoachResponseParser.parse(rawModelOutput)
            ?? CoachResponse(responseType: .insight, title: "", summary: rawModelOutput)
        return parsed.adaptiveShaped()
    }

    static func run(_ c: RoutingEvalCase) -> EvalResult {
        let role = AgentRouter.route(userText: c.userText, hasImage: c.hasImage)
        let ok = role == c.expectedRole
        return EvalResult(name: c.name, passed: ok,
                          failures: ok ? [] : ["routed to \(role.rawValue), expected \(c.expectedRole.rawValue)"])
    }

    static func run(_ c: ShapeEvalCase) -> EvalResult {
        let response = shaped(c.rawModelOutput)
        let failures = c.assertions.compactMap { a -> String? in
            a.check(response).map { "\(a.label): \($0)" }
        }
        return EvalResult(name: c.name, passed: failures.isEmpty, failures: failures)
    }

    /// Run every default case. Used by tests and the in-app quality readout.
    static func runAll() -> [EvalResult] {
        routingCases.map(run) + shapeCases.map(run)
    }
}
