import XCTest
@testable import PulseLoop

/// Tests for the shared `NetworkRetry` backoff utility using a fake transport.
final class NetworkRetryTests: XCTestCase {

    /// Records each request and returns scripted responses/errors in order.
    actor FakeTransport: HTTPTransport {
        enum Step {
            case status(Int)
            case error(Error)
        }
        private let steps: [Step]
        private var calls = 0

        init(_ steps: [Step]) { self.steps = steps }

        var callCount: Int { calls }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            let index = calls
            calls += 1
            let step = steps[min(index, steps.count - 1)]
            switch step {
            case .status(let code):
                let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
                return (Data(), response)
            case .error(let error):
                throw error
            }
        }
    }

    private func request() -> URLRequest {
        URLRequest(url: URL(string: "https://example.com")!)
    }

    func testSuccessFirstTryNoRetry() async throws {
        let transport = FakeTransport([.status(200)])
        let (_, response) = try await NetworkRetry.send(request(), transport: transport, initialDelay: 0.001)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let count = await transport.callCount
        XCTAssertEqual(count, 1)
    }

    func testRetriesOn500ThenSucceeds() async throws {
        let transport = FakeTransport([.status(500), .status(503), .status(200)])
        let (_, response) = try await NetworkRetry.send(request(), transport: transport, maxAttempts: 3, initialDelay: 0.001)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let count = await transport.callCount
        XCTAssertEqual(count, 3)
    }

    func testRetriesOn429() async throws {
        let transport = FakeTransport([.status(429), .status(200)])
        let (_, response) = try await NetworkRetry.send(request(), transport: transport, maxAttempts: 3, initialDelay: 0.001)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let count = await transport.callCount
        XCTAssertEqual(count, 2)
    }

    func testDoesNotRetryOn404() async throws {
        let transport = FakeTransport([.status(404), .status(200)])
        let (_, response) = try await NetworkRetry.send(request(), transport: transport, maxAttempts: 3, initialDelay: 0.001)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 404)
        let count = await transport.callCount
        XCTAssertEqual(count, 1)
    }

    func testExhaustsRetriesAndReturnsLast5xx() async throws {
        let transport = FakeTransport([.status(500), .status(500), .status(500)])
        let (_, response) = try await NetworkRetry.send(request(), transport: transport, maxAttempts: 3, initialDelay: 0.001)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 500)
        let count = await transport.callCount
        XCTAssertEqual(count, 3)
    }

    func testRetriesTransportErrorThenThrows() async {
        let err = URLError(.timedOut)
        let transport = FakeTransport([.error(err), .error(err), .error(err)])
        do {
            _ = try await NetworkRetry.send(request(), transport: transport, maxAttempts: 3, initialDelay: 0.001)
            XCTFail("Expected throw")
        } catch {
            let count = await transport.callCount
            XCTAssertEqual(count, 3)
        }
    }
}
