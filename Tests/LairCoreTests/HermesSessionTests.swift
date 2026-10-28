import Foundation
@testable import LairCore
import Synchronization
import Testing

@Suite(.serialized)
struct HermesSessionTests {
    private let base = URL(string: "http://hermes.test:8642")!

    @Test func sendsTheTurnWithAuthAndSessionHeaders() throws {
        let session = HermesSession(baseURL: base, credentials: .init(apiKey: "k", accessClientID: "id",
                                                                      accessClientSecret: "secret"))
        let first = try session.request(for: "Hello")
        let second = try session.request(for: "Again")
        #expect(first.url?.absoluteString == "http://hermes.test:8642/v1/chat/completions")
        #expect(first.value(forHTTPHeaderField: "Authorization") == "Bearer k")
        #expect(first.value(forHTTPHeaderField: "CF-Access-Client-Id") == "id")
        #expect(first.value(forHTTPHeaderField: "CF-Access-Client-Secret") == "secret")
        let sessionID = try #require(first.value(forHTTPHeaderField: "X-Hermes-Session-Id"))
        #expect(second.value(forHTTPHeaderField: "X-Hermes-Session-Id") == sessionID)

        let data = try #require(first.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(body["model"] as? String == "hermes-agent")
        #expect(body["stream"] as? Bool == true)
        #expect(messages.last == ["role": "user", "content": "Hello"])
    }

    @Test func leavesOutAccessHeadersWithoutAToken() throws {
        let request = try HermesSession(baseURL: base, credentials: .init(apiKey: "k")).request(for: "Hi")
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == nil)
    }

    @Test func eachCallGetsItsOwnSession() throws {
        let one = try HermesSession(baseURL: base, credentials: .init(apiKey: "k")).request(for: "Hi")
        let two = try HermesSession(baseURL: base, credentials: .init(apiKey: "k")).request(for: "Hi")
        #expect(one.value(forHTTPHeaderField: "X-Hermes-Session-Id") != two.value(forHTTPHeaderField: "X-Hermes-Session-Id"))
    }

    @Test func streamsTheReplyText() async throws {
        StubServer.reply = (200, """
            : keepalive

            event: hermes.tool.progress
            data: {"choices":[{"delta":{"content":"🔧 web_search"}}]}

            data: {"choices":[{"delta":{"content":"It is "}}]}

            data: {"choices":[{"delta":{"content":"sunny."}}]}

            data: [DONE]

            """)
        URLProtocol.registerClass(StubServer.self)
        defer { URLProtocol.unregisterClass(StubServer.self) }

        var text = ""
        for try await delta in try HermesSession(baseURL: base, credentials: .init(apiKey: "k")).ask("Weather?") {
            text += delta
        }
        #expect(text == "It is sunny.")
    }

    @Test func failsOnAnErrorStatus() async throws {
        StubServer.reply = (401, "")
        URLProtocol.registerClass(StubServer.self)
        defer { URLProtocol.unregisterClass(StubServer.self) }

        await #expect(throws: HermesSession.Failure.self) {
            for try await _ in try HermesSession(baseURL: base, credentials: .init(apiKey: "bad")).ask("Hi") {}
        }
    }
}

/// Answers every request to `hermes.test` with a canned status and body.
final class StubServer: URLProtocol {
    nonisolated(unsafe) static var reply: (status: Int, body: String) = (200, "")

    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "hermes.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.reply.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
