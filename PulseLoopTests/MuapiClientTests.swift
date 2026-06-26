import Foundation
import XCTest
@testable import PulseLoop

// MARK: - MuapiClient tests (multifunction roadmap M2)
//
// Exercises the submit-then-poll flow, sandbox header, output normalization, model
// catalog parsing, and cancellation/timeout — all through a mocked transport so no
// network or real API key is needed.

final class MuapiClientTests: XCTestCase {

    // MARK: Test doubles

    /// In-memory key store so the client always "has" a key.
    private struct StubKeyStore: APIKeyStore {
        var key: String? = "test-key"
        func readKey() throws -> String? { key }
        func saveKey(_ key: String) throws {}
        func deleteKey() throws {}
    }

    /// Returns canned responses keyed by URL substring; records sent headers.
    private final class MockTransport: MuapiTransport, @unchecked Sendable {
        var responses: [(match: String, status: Int, body: Data)] = []
        var capturedHeaders: [[String: String]] = []
        var requestCount = 0

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            requestCount += 1
            capturedHeaders.append(request.allHTTPHeaderFields ?? [:])
            let path = request.url?.absoluteString ?? ""
            let match = responses.first { path.contains($0.match) } ?? responses.first!
            let http = HTTPURLResponse(url: request.url!, statusCode: match.status, httpVersion: nil, headerFields: nil)!
            return (match.body, http)
        }
    }

    private func json(_ obj: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: obj)
    }

    // MARK: submit + poll

    func testGenerateSubmitsThenPollsToCompletion() async throws {
        let transport = MockTransport()
        transport.responses = [
            (match: "predictions", status: 200, body: json(["status": "completed", "outputs": ["https://cdn.muapi.ai/a.png"]])),
            (match: "flux-schnell", status: 200, body: json(["request_id": "req_123"])),
        ]
        let client = MuapiClient(transport: transport, keyStore: StubKeyStore(), sandbox: false, pollInterval: 0.001, pollTimeout: 5)

        let result = try await client.generate(model: "flux-schnell", params: ["prompt": "a cat"])

        XCTAssertEqual(result.requestID, "req_123")
        XCTAssertTrue(result.isCompleted)
        XCTAssertEqual(result.outputs, [URL(string: "https://cdn.muapi.ai/a.png")!])
    }

    func testPollWaitsThroughProcessingThenCompletes() async throws {
        let transport = MockTransport()
        // First poll: processing. We can't easily sequence different bodies for the
        // same match with this simple mock, so assert the processing→retry path via
        // a body that flips after first read.
        final class Flipper: MuapiTransport, @unchecked Sendable {
            var calls = 0
            func data(for request: URLRequest) async throws -> (Data, URLResponse) {
                calls += 1
                let body: [String: Any]
                if request.url!.absoluteString.contains("predictions") {
                    body = calls <= 2 ? ["status": "processing"] : ["status": "completed", "outputs": ["https://cdn.muapi.ai/v.mp4"]]
                } else {
                    body = ["request_id": "req_v"]
                }
                let data = try! JSONSerialization.data(withJSONObject: body)
                let http = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (data, http)
            }
        }
        let client = MuapiClient(transport: Flipper(), keyStore: StubKeyStore(), sandbox: false, pollInterval: 0.001, pollTimeout: 5)
        let result = try await client.generate(model: "kling-v2-master", params: [:])
        XCTAssertEqual(result.outputs.first?.absoluteString, "https://cdn.muapi.ai/v.mp4")
    }

    func testSandboxSetsHeader() async throws {
        let transport = MockTransport()
        transport.responses = [
            (match: "predictions", status: 200, body: json(["status": "completed", "outputs": ["https://x/y.png"]])),
            (match: "flux-schnell", status: 200, body: json(["request_id": "r"])),
        ]
        let client = MuapiClient(transport: transport, keyStore: StubKeyStore(), sandbox: true, pollInterval: 0.001, pollTimeout: 5)
        _ = try await client.generate(model: "flux-schnell", params: [:])
        XCTAssertTrue(transport.capturedHeaders.contains { $0["x-sandbox"] == "true" })
        XCTAssertTrue(transport.capturedHeaders.allSatisfy { $0["x-api-key"] == "test-key" })
    }

    func testMissingKeyThrows() async throws {
        let transport = MockTransport()
        transport.responses = [(match: "flux", status: 200, body: json(["request_id": "r"]))]
        let client = MuapiClient(transport: transport, keyStore: StubKeyStore(key: nil), sandbox: false)
        do {
            _ = try await client.submit(model: "flux-schnell", params: [:])
            XCTFail("expected missingAPIKey")
        } catch MuapiError.missingAPIKey {
            // expected
        }
    }

    func testHTTPErrorSurfaces() async throws {
        let transport = MockTransport()
        transport.responses = [(match: "flux", status: 402, body: Data("insufficient balance".utf8))]
        let client = MuapiClient(transport: transport, keyStore: StubKeyStore(), sandbox: false)
        do {
            _ = try await client.submit(model: "flux-schnell", params: [:])
            XCTFail("expected http error")
        } catch MuapiError.http(let code, _) {
            XCTAssertEqual(code, 402)
        }
    }

    // MARK: output normalization

    func testExtractOutputsHandlesShapes() {
        XCTAssertEqual(
            MuapiClient.extractOutputs(["outputs": ["https://a/1.png", "https://a/2.png"]]).count, 2)
        XCTAssertEqual(
            MuapiClient.extractOutputs(["outputs": [["url": "https://a/1.png"]]]).first?.absoluteString,
            "https://a/1.png")
        XCTAssertEqual(
            MuapiClient.extractOutputs(["output": "https://a/single.mp4"]).first?.absoluteString,
            "https://a/single.mp4")
        XCTAssertTrue(MuapiClient.extractOutputs([:]).isEmpty)
    }

    func testExtractTextHandlesShapes() {
        XCTAssertEqual(MuapiClient.extractText(["text": "hello"]), "hello")
        XCTAssertEqual(MuapiClient.extractText(["output": "hi"]), "hi")
        XCTAssertEqual(MuapiClient.extractText(["outputs": ["a", "b"]]), "a\nb")
        XCTAssertEqual(MuapiClient.extractText(["outputs": [["text": "deep"]]]), "deep")
        XCTAssertEqual(MuapiClient.extractText(["output": ["content": "obj"]]), "obj")
        XCTAssertNil(MuapiClient.extractText([:]))
    }

    func testTextModelCatalogPresent() {
        XCTAssertFalse(MuapiCatalog.text.isEmpty)
        XCTAssertTrue(MuapiCatalog.all.contains { $0.category == "text" })
    }

    // MARK: catalog

    func testParseModelsBareArrayAndWrapped() throws {
        let bare = Data("""
        [{"name":"flux-schnell","category":"image","cost_usd":0.003}]
        """.utf8)
        XCTAssertEqual(try MuapiClient.parseModels(bare).first?.name, "flux-schnell")

        let wrapped = Data("""
        {"models":[{"name":"veo3","category":"video"}]}
        """.utf8)
        XCTAssertEqual(try MuapiClient.parseModels(wrapped).first?.name, "veo3")
    }

    func testCuratedCatalogDefaults() {
        XCTAssertEqual(MuapiCatalog.defaultModel(for: .image), "nano-banana")
        XCTAssertEqual(MuapiCatalog.defaultModel(for: .edit), "nano-banana")
        XCTAssertEqual(MuapiCatalog.defaultModel(for: .video), "openai-sora-2-text-to-video")
        XCTAssertNotNil(MuapiCatalog.cost(for: "nano-banana"))
        XCTAssertNotNil(MuapiCatalog.cost(for: "openai-sora-2-text-to-video"))
        XCTAssertFalse(MuapiCatalog.all.isEmpty)
    }

    // MARK: cancellation + timeout

    func testCancellationStopsPolling() async throws {
        final class NeverDone: MuapiTransport, @unchecked Sendable {
            func data(for request: URLRequest) async throws -> (Data, URLResponse) {
                let body = try! JSONSerialization.data(withJSONObject: ["status": "processing"])
                let http = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (body, http)
            }
        }
        let client = MuapiClient(transport: NeverDone(), keyStore: StubKeyStore(), sandbox: false, pollInterval: 0.01, pollTimeout: 10)
        let task = Task { try await client.pollResult(requestID: "r") }
        try await Task.sleep(nanoseconds: 30_000_000)
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("expected cancellation")
        } catch is CancellationError {
            // expected
        } catch MuapiError.cancelled {
            // also acceptable
        }
    }

    func testTimeoutThrows() async throws {
        final class NeverDone: MuapiTransport, @unchecked Sendable {
            func data(for request: URLRequest) async throws -> (Data, URLResponse) {
                let body = try! JSONSerialization.data(withJSONObject: ["status": "processing"])
                let http = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (body, http)
            }
        }
        let client = MuapiClient(transport: NeverDone(), keyStore: StubKeyStore(), sandbox: false, pollInterval: 0.001, pollTimeout: 0.02)
        do {
            _ = try await client.pollResult(requestID: "r")
            XCTFail("expected timeout")
        } catch MuapiError.timedOut {
            // expected
        }
    }

    // MARK: retry

    func testRetriesTransient5xxThenSucceeds() async throws {
        final class FlakyTransport: MuapiTransport, @unchecked Sendable {
            var calls = 0
            func data(for request: URLRequest) async throws -> (Data, URLResponse) {
                calls += 1
                // First submit attempt 503, retry succeeds.
                let status = calls == 1 ? 503 : 200
                let body = try! JSONSerialization.data(withJSONObject: ["request_id": "r"])
                let http = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
                return (body, http)
            }
        }
        let flaky = FlakyTransport()
        let client = MuapiClient(transport: flaky, keyStore: StubKeyStore(), sandbox: false, pollInterval: 0.001, pollTimeout: 5)
        let id = try await client.submit(model: "flux-schnell", params: [:])
        XCTAssertEqual(id, "r")
        XCTAssertGreaterThanOrEqual(flaky.calls, 2)
    }

    // MARK: moderation

    func testModeratorApprovesNormalPrompt() {
        XCTAssertEqual(MediaModerator.moderate(prompt: "a serene mountain at sunrise"), .approved)
    }

    func testModeratorRejectsDisallowed() {
        if case .rejected = MediaModerator.moderate(prompt: "how to make a bomb diagram") {
            // expected
        } else {
            XCTFail("expected rejection")
        }
    }

    func testModeratorFlagsBorderline() {
        if case .flagged = MediaModerator.moderate(prompt: "a portrait of a famous politician") {
            // expected
        } else {
            XCTFail("expected flag")
        }
    }
}
