import Foundation
import SwiftData
import XCTest
@testable import PulseLoop

// MARK: - Stubs

/// In-memory ResponsesClient that replays a scripted queue of responses.
actor StubResponsesClient: ResponsesClient {
    private var queue: [OpenAIResponse]
    private(set) var sendCount = 0
    init(_ responses: [OpenAIResponse]) { self.queue = responses }
    func send(requestBody: Data) async throws -> OpenAIResponse {
        sendCount += 1
        return queue.isEmpty ? OpenAIResponse(id: "empty", outputItems: []) : queue.removeFirst()
    }
}

/// URLProtocol that returns a fixed body/status for the Responses client test.
final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseBody = Data()
    nonisolated(unsafe) static var statusCode = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.statusCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private func validResponseJSON(title: String = "Today") -> String {
    """
    {"response_type":"insight","title":"\(title)","summary":"You did well.","bullets":["A","B"],\
    "chart":null,"safety_note":null,"data_quality_note":null,"sources":[],\
    "follow_up_chips":["More"],"actions_taken":[],"confidence":"high"}
    """
}

// MARK: - Schema

final class CoachSchemaTests: XCTestCase {
    func testDecodeValidResponse() throws {
        let r = try XCTUnwrap(CoachResponse.decode(fromJSON: validResponseJSON()))
        XCTAssertEqual(r.responseType, .insight)
        XCTAssertEqual(r.title, "Today")
        XCTAssertEqual(r.bullets, ["A", "B"])
        XCTAssertEqual(r.confidence, .high)
    }

    func testRejectsMissingRequiredField() {
        // No response_type / summary → decode must fail.
        XCTAssertNil(CoachResponse.decode(fromJSON: #"{"title":"x"}"#))
    }

    func testParserStripsCodeFenceAndProse() {
        let fenced = "```json\n\(validResponseJSON())\n```"
        XCTAssertNotNil(CoachResponseParser.parse(fenced))
        let prose = "Here you go:\n\(validResponseJSON())\nHope that helps!"
        XCTAssertNotNil(CoachResponseParser.parse(prose))
    }

    func testStrictSchemaIsSerializable() {
        XCTAssertTrue(JSONSerialization.isValidJSONObject(CoachResponseSchema.jsonSchema))
        let format = CoachResponseSchema.textFormat
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(format["strict"] as? Bool, true)
    }

    func testChartRoundTrips() throws {
        let chart = CoachChart(chartType: .bar, title: "Steps", metric: .steps,
                               range: CoachChartRange(start: "2026-05-01", end: "2026-05-07"),
                               data: [CoachChartPoint(x: "2026-05-01", y: 8000, series: nil)])
        let response = CoachResponse(responseType: .insightWithChart, title: "T", summary: "S", chart: chart)
        let json = try XCTUnwrap(response.encodedJSON())
        let decoded = try XCTUnwrap(CoachResponse.decode(fromJSON: json))
        XCTAssertEqual(decoded.chart?.chartType, .bar)
        XCTAssertEqual(decoded.chart?.data.first?.y, 8000)
    }

    func testMediaRoundTrips() throws {
        let media = CoachMedia(kind: .image, urls: ["https://cdn.muapi.ai/a.png"],
                               prompt: "a cat", model: "flux-schnell", sandbox: true)
        let response = CoachResponse(responseType: .insight, title: "T", summary: "S", media: [media])
        let json = try XCTUnwrap(response.encodedJSON())
        let decoded = try XCTUnwrap(CoachResponse.decode(fromJSON: json))
        XCTAssertEqual(decoded.media.count, 1)
        XCTAssertEqual(decoded.media.first?.kind, .image)
        XCTAssertEqual(decoded.media.first?.urls.first, "https://cdn.muapi.ai/a.png")
        XCTAssertEqual(decoded.media.first?.model, "flux-schnell")
        XCTAssertTrue(decoded.media.first?.sandbox ?? false)
    }

    func testOldResponseWithoutMediaStillDecodes() throws {
        // Older persisted payloads have no `media` key → must decode to empty.
        let decoded = try XCTUnwrap(CoachResponse.decode(fromJSON: validResponseJSON()))
        XCTAssertTrue(decoded.media.isEmpty)
    }

    func testDiagramRoundTrips() throws {
        let diagram = CoachDiagram(kind: .mermaid, title: "Flow", source: "graph TD; A-->B")
        let response = CoachResponse(responseType: .insight, title: "T", summary: "S", diagram: diagram)
        let json = try XCTUnwrap(response.encodedJSON())
        let decoded = try XCTUnwrap(CoachResponse.decode(fromJSON: json))
        XCTAssertEqual(decoded.diagram?.kind, .mermaid)
        XCTAssertEqual(decoded.diagram?.title, "Flow")
        XCTAssertEqual(decoded.diagram?.source, "graph TD; A-->B")
    }

    func testOldResponseWithoutDiagramStillDecodes() throws {
        // Payloads with no `diagram` key → diagram is nil, not a decode failure.
        let decoded = try XCTUnwrap(CoachResponse.decode(fromJSON: validResponseJSON()))
        XCTAssertNil(decoded.diagram)
    }

    func testDiagramSchemaIsRequiredAndSerializable() throws {
        let schema = CoachResponseSchema.jsonSchema
        XCTAssertTrue(JSONSerialization.isValidJSONObject(schema))
        let required = schema["required"] as? [String] ?? []
        XCTAssertTrue(required.contains("diagram"))
        let props = schema["properties"] as? [String: Any] ?? [:]
        XCTAssertNotNil(props["diagram"])
    }
}

// MARK: - Analysis engine

final class AnalysisEngineTests: XCTestCase {
    func testTrendRising() {
        let base = Date()
        let series = (0..<5).map { (Calendar.current.date(byAdding: .day, value: $0, to: base)!, Double($0 * 100)) }
        let t = AnalysisEngine.trend(series)
        XCTAssertEqual(t.direction, "rising")
        XCTAssertEqual(t.changeAbsolute, 400)
    }

    func testCorrelationPerfectPositive() {
        let r = AnalysisEngine.correlation([(1, 2), (2, 4), (3, 6), (4, 8)])
        XCTAssertEqual(r.pearson ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(r.strength, "strong")
    }

    func testDistribution() {
        let d = AnalysisEngine.distribution([1, 2, 3, 4, 5])
        XCTAssertEqual(d.median, 3)
        XCTAssertEqual(d.min, 1)
        XCTAssertEqual(d.max, 5)
    }

    func testOutlierDetected() {
        var values = Array(repeating: 100.0, count: 8)
        values.append(1000)
        let series = values.enumerated().map { (Calendar.current.date(byAdding: .day, value: $0.offset, to: Date())!, $0.element) }
        XCTAssertFalse(AnalysisEngine.outliers(series).isEmpty)
    }
}

// MARK: - Tools

@MainActor
final class CoachToolTests: XCTestCase {
    private func context() throws -> ModelContext { try TestSupport.makeContext() }

    private func ctx(_ modelContext: ModelContext) -> ToolExecutionContext {
        ToolExecutionContext(modelContext: modelContext, flags: CoachFeatureFlags(settings: .default, hasAPIKey: false))
    }

    func testDailySummaryReturnsActivity() async throws {
        let c = try context()
        let today = CoachDataAccess.localDateString(Date())
        TestSupport.insertActivity(date: Date(), steps: 8200, calories: 410, into: c)
        TestSupport.insertMeasurement(kind: .heartRate, value: 72, timestamp: Date(), into: c)

        let tool = try XCTUnwrap(ToolRegistry(flags: ctx(c).flags).tool(named: "get_daily_summary"))
        let result = try await tool.run(Data(#"{"date":"\#(today)"}"#.utf8), ctx(c))
        let obj = try parse(result)
        XCTAssertEqual((obj["data_available"] as? Bool), true)
        let activity = try XCTUnwrap(obj["activity"] as? [String: Any])
        XCTAssertEqual(activity["steps"] as? Int, 8200)
    }

    func testMetricSeriesFiltersToRange() async throws {
        let c = try context()
        TestSupport.insertActivity(date: TestSupport.day(0), steps: 5000, into: c)
        TestSupport.insertActivity(date: TestSupport.day(-1), steps: 6000, into: c)
        TestSupport.insertActivity(date: TestSupport.day(-40), steps: 9999, into: c)

        let start = CoachDataAccess.localDateString(TestSupport.day(-7))
        let end = CoachDataAccess.localDateString(TestSupport.day(0))
        let tool = try XCTUnwrap(ToolRegistry(flags: ctx(c).flags).tool(named: "get_metric_series"))
        let result = try await tool.run(Data(#"{"metric":"steps","start":"\#(start)","end":"\#(end)","granularity":"day"}"#.utf8), ctx(c))
        let obj = try parse(result)
        XCTAssertEqual(obj["count"] as? Int, 2)  // the -40d row is excluded
    }

    func testHRRawSeriesKeepsIntradayPointsButDailyCollapses() throws {
        let c = try context()
        let day = "2026-06-01"
        let base = try XCTUnwrap(CoachDataAccess.parseLocalDate(day))
        for h in [8, 12, 18] {
            TestSupport.insertMeasurement(kind: .heartRate, value: Double(60 + h),
                                          timestamp: base.addingTimeInterval(Double(h) * 3600), into: c)
        }
        let raw = CoachDataAccess.seriesPoints(metric: .hr, start: day, end: day, granularity: "raw", context: c)
        XCTAssertEqual(raw.count, 3)  // intraday readings preserved
        let daily = CoachDataAccess.seriesPoints(metric: .hr, start: day, end: day, granularity: "day", context: c)
        XCTAssertEqual(daily.count, 1)  // one daily average
    }

    func testPrepareChartEmbedsData() async throws {
        let c = try context()
        TestSupport.insertActivity(date: TestSupport.day(0), steps: 8000, into: c)
        TestSupport.insertActivity(date: TestSupport.day(-1), steps: 7000, into: c)

        let start = CoachDataAccess.localDateString(TestSupport.day(-6))
        let end = CoachDataAccess.localDateString(TestSupport.day(0))
        let tool = try XCTUnwrap(ToolRegistry(flags: ctx(c).flags).tool(named: "prepare_chart"))
        let result = try await tool.run(Data(#"{"chart_type":"bar","title":"Steps","metric":"steps","start":"\#(start)","end":"\#(end)","granularity":"day","annotations":[]}"#.utf8), ctx(c))
        // The returned `chart` must decode as a CoachChart (verbatim-copy contract).
        let obj = try parse(result)
        let chartData = try JSONSerialization.data(withJSONObject: try XCTUnwrap(obj["chart"]))
        let chart = try XCTUnwrap(CoachChart.decode(chartData))
        XCTAssertEqual(chart.chartType, .bar)
        XCTAssertEqual(chart.data.count, 2)
    }

    func testRegistryHasReadOnlyToolsOnly() {
        // Writes now default ON; to verify read-only gating still works, explicitly
        // disable writes and assert write tools are absent.
        var settings = CoachSettings.default
        settings.enableWriteTools = false
        let registry = ToolRegistry(flags: CoachFeatureFlags(settings: settings, hasAPIKey: true))
        let names = Set(registry.toolSpecs.compactMap { $0["name"] as? String })
        XCTAssertTrue(names.contains("get_daily_summary"))
        XCTAssertTrue(names.contains("prepare_chart"))
        XCTAssertTrue(names.contains("analyze_trend"))
        XCTAssertFalse(names.contains("set_goal"))           // Milestone B
        XCTAssertFalse(names.contains("delete_activity_session"))
    }

    private func parse(_ result: ToolResult) throws -> [String: Any] {
        let data = Data(result.jsonString.utf8)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

// MARK: - Orchestrator

@MainActor
final class CoachOrchestratorTests: XCTestCase {
    private func packet(_ c: ModelContext) -> CoachContextPacket { CoachContextBuilder.build(context: c) }

    /// Coach is opt-out by default; tests exercising the LLM path need it on.
    private var enabledSettings: CoachSettings {
        var s = CoachSettings.default
        s.coachMasterEnabled = true
        return s
    }

    /// Genuinely-off coach. The master switch defaults to on, and the paired-proxy
    /// path can otherwise make `coachEnabled` true even without an on-device key, so
    /// "disabled" must flip the master switch explicitly to be deterministic.
    private var disabledSettings: CoachSettings {
        var s = CoachSettings.default
        s.coachMasterEnabled = false
        return s
    }

    private func orchestrator(client: ResponsesClient, flags: CoachFeatureFlags, context: ModelContext) -> CoachOrchestrator {
        CoachOrchestrator(client: client, registry: ToolRegistry(flags: flags), flags: flags,
                          toolContext: ToolExecutionContext(modelContext: context, flags: flags))
    }

    func testDisabledCoachUsesScriptedFallback() async throws {
        let c = try TestSupport.makeContext()
        TestSupport.insertActivity(date: Date(), steps: 7000, into: c)
        let flags = CoachFeatureFlags(settings: disabledSettings, hasAPIKey: false)  // disabled
        let o = orchestrator(client: StubResponsesClient([]), flags: flags, context: c)
        let result = await o.runTurn(userText: "How am I doing?", packet: packet(c), recentMessages: [])
        XCTAssertEqual(result.assistant.responseType, .insight)
        XCTAssertTrue(result.assistant.bullets.contains { $0.contains("7000") })
    }

    func testMessageOnlyResponseIsParsed() async throws {
        let c = try TestSupport.makeContext()
        let flags = CoachFeatureFlags(settings: enabledSettings, hasAPIKey: true)
        let stub = StubResponsesClient([OpenAIResponse(id: "r1", outputItems: [.message(text: validResponseJSON(title: "Hi"))])])
        let o = orchestrator(client: stub, flags: flags, context: c)
        let result = await o.runTurn(userText: "hi", packet: packet(c), recentMessages: [])
        XCTAssertEqual(result.assistant.title, "Hi")
        XCTAssertTrue(result.trace.isEmpty)
    }

    func testToolCallThenFinalRecordsTrace() async throws {
        let c = try TestSupport.makeContext()
        TestSupport.insertActivity(date: Date(), steps: 8200, into: c)
        let today = CoachDataAccess.localDateString(Date())
        let flags = CoachFeatureFlags(settings: enabledSettings, hasAPIKey: true)
        let stub = StubResponsesClient([
            OpenAIResponse(id: "r1", outputItems: [.functionCall(.init(name: "get_daily_summary", callID: "c1", arguments: #"{"date":"\#(today)"}"#))]),
            OpenAIResponse(id: "r2", outputItems: [.message(text: validResponseJSON())]),
        ])
        let o = orchestrator(client: stub, flags: flags, context: c)
        var traceEvents: [CoachTraceEvent] = []
        let result = await o.runTurn(userText: "today?", packet: packet(c), recentMessages: []) { traceEvents.append($0) }
        XCTAssertEqual(result.trace.count, 1)
        XCTAssertEqual(result.trace.first?.toolName, "get_daily_summary")
        XCTAssertEqual(result.trace.first?.status, "success")
        XCTAssertTrue(traceEvents.contains { $0.status == .runningTool })
    }

    func testUnparseableFinalFallsBack() async throws {
        let c = try TestSupport.makeContext()
        let flags = CoachFeatureFlags(settings: enabledSettings, hasAPIKey: true)
        // Every response is empty (no usable content at all) → repair loop exhausts
        // → graceful fallback.
        let empty = OpenAIResponse(id: "x", outputItems: [.message(text: "")])
        let o = orchestrator(client: StubResponsesClient([empty, empty, empty, empty]), flags: flags, context: c)
        let result = await o.runTurn(userText: "hi", packet: packet(c), recentMessages: [])
        XCTAssertEqual(result.assistant.responseType, .errorRecovery)
    }

    func testProseFinalIsSalvagedNotFallback() async throws {
        let c = try TestSupport.makeContext()
        let flags = CoachFeatureFlags(settings: enabledSettings, hasAPIKey: true)
        // A model that ignores the JSON contract but gives a real prose answer should
        // have that answer salvaged (wrapped), not replaced by a canned fallback.
        let prose = OpenAIResponse(id: "p", outputItems: [.message(text: "Your resting heart rate looks healthy and stable.")])
        let o = orchestrator(client: StubResponsesClient([prose, prose, prose, prose]), flags: flags, context: c)
        let result = await o.runTurn(userText: "how's my heart?", packet: packet(c), recentMessages: [])
        XCTAssertNotEqual(result.assistant.responseType, .errorRecovery)
        XCTAssertTrue(result.assistant.summary.contains("resting heart rate"))
    }
}

// MARK: - HTTP client

final class OpenAIResponsesClientTests: XCTestCase {
    func testParsesFunctionCallAndText() async throws {
        StubURLProtocol.statusCode = 200
        StubURLProtocol.responseBody = Data("""
        {"id":"resp_1","output":[
          {"type":"function_call","name":"get_daily_summary","call_id":"call_1","arguments":"{\\"date\\":\\"2026-06-01\\"}"},
          {"type":"message","content":[{"type":"output_text","text":"hello"}]}
        ]}
        """.utf8)

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let client = OpenAIResponsesClient(apiKey: "sk-test", session: URLSession(configuration: config))

        let body = try OpenAIRequestBuilder.data(model: "gpt-5.4", input: [], tools: [], textFormat: nil, previousResponseId: nil, reasoningEffort: nil)
        let response = try await client.send(requestBody: body)
        XCTAssertEqual(response.functionCalls.count, 1)
        XCTAssertEqual(response.functionCalls.first?.name, "get_daily_summary")
        XCTAssertEqual(response.outputText, "hello")
    }

    func testHTTPErrorThrows() async {
        StubURLProtocol.statusCode = 401
        StubURLProtocol.responseBody = Data(#"{"error":"bad key"}"#.utf8)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let client = OpenAIResponsesClient(apiKey: "sk-test", session: URLSession(configuration: config))
        do {
            _ = try await client.send(requestBody: Data("{}".utf8))
            XCTFail("expected error")
        } catch {
            // expected
        }
    }
}

private extension CoachChart {
    static func decode(_ data: Data) -> CoachChart? { try? JSONDecoder().decode(CoachChart.self, from: data) }
}

// MARK: - Provider matrix (roadmap B1)

final class CoachProviderMatrixTests: XCTestCase {
    func testShippingMatrix() {
        XCTAssertTrue(CoachProviderMode.userOpenAIKey.isShippable)
        XCTAssertTrue(CoachProviderMode.backendProxy.isShippable)
        XCTAssertFalse(CoachProviderMode.offlineStub.isShippable, "offlineStub is dev/test only")
        XCTAssertFalse(CoachProviderMode.bedrock.isShippable, "bedrock is experimental, not in the launch matrix")
    }

    func testSelectableModesNeverOfferNonShippingInRelease() {
        // selectableModes is the only list a provider picker may use. In a release
        // build it must contain exactly the shipping matrix; DEBUG may add more.
        let selectable = CoachProviderMode.selectableModes
        XCTAssertTrue(selectable.contains(.userOpenAIKey))
        XCTAssertTrue(selectable.contains(.backendProxy))
        #if DEBUG
        XCTAssertEqual(Set(selectable), Set(CoachProviderMode.allCases))
        #else
        XCTAssertFalse(selectable.contains(.offlineStub))
        XCTAssertFalse(selectable.contains(.bedrock))
        XCTAssertTrue(selectable.allSatisfy { $0.isShippable })
        #endif
    }

    // MARK: - coachEnabled gating across provider modes (roadmap C3)

    func testBackendProxyEnablesCoachWithoutOnDeviceKey() {
        var s = CoachSettings()
        s.coachMasterEnabled = true
        s.providerMode = .backendProxy
        s.backendProxyURL = "https://pulseloop.example.com"
        // No on-device key — the server holds it. The coach must still be enabled.
        let flags = CoachFeatureFlags(settings: s, hasAPIKey: false)
        XCTAssertTrue(flags.coachEnabled)
        XCTAssertTrue(flags.statusLine.contains("Ready"))
    }

    func testBackendProxyDisabledWhenURLMissing() {
        var s = CoachSettings()
        s.coachMasterEnabled = true
        s.providerMode = .backendProxy
        s.backendProxyURL = "   "
        let flags = CoachFeatureFlags(settings: s, hasAPIKey: false)
        // When a paired PulseLoop proxy is available (zero-config path), the coach
        // is enabled even without an explicit URL. This test only asserts the
        // URL-gating when no paired proxy exists.
        if !CoachFeatureFlags.pairedProxyAvailable {
            XCTAssertFalse(flags.coachEnabled)
        }
    }

    func testByoKeyModeStillRequiresKey() {
        var s = CoachSettings()
        s.coachMasterEnabled = true
        s.providerMode = .userOpenAIKey
        // Without a key AND without a paired proxy, BYO-key mode stays disabled.
        if !CoachFeatureFlags.pairedProxyAvailable {
            XCTAssertFalse(CoachFeatureFlags(settings: s, hasAPIKey: false).coachEnabled)
        }
        XCTAssertTrue(CoachFeatureFlags(settings: s, hasAPIKey: true).coachEnabled)
    }

    func testMasterSwitchOffDisablesEveryMode() {
        for mode in CoachProviderMode.allCases {
            var s = CoachSettings()
            s.coachMasterEnabled = false
            s.providerMode = mode
            s.backendProxyURL = "https://pulseloop.example.com"
            XCTAssertFalse(CoachFeatureFlags(settings: s, hasAPIKey: true).coachEnabled)
        }
    }
}
