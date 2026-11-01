import Foundation
@testable import LairCore
import Synchronization
import Testing

@Suite(.serialized)
struct HermesSessionTests {
    private let base = URL(string: "http://hermes.test:8642")!

    @Test func sendsTheTurnWithAuthAndSessionHeaders() throws {
        let session = HermesSession(baseURL: base, credentials: .init(apiKey: "k", headers: [
            "CF-Access-Client-Id": "id", "X-Proxy-Token": "secret",
        ]))
        let first = try session.request(for: "Hello")
        let second = try session.request(for: "Again")
        #expect(first.url?.absoluteString == "http://hermes.test:8642/v1/chat/completions")
        #expect(first.value(forHTTPHeaderField: "Authorization") == "Bearer k")
        #expect(first.value(forHTTPHeaderField: "CF-Access-Client-Id") == "id")
        #expect(first.value(forHTTPHeaderField: "X-Proxy-Token") == "secret")
        let sessionID = try #require(first.value(forHTTPHeaderField: "X-Hermes-Session-Id"))
        #expect(second.value(forHTTPHeaderField: "X-Hermes-Session-Id") == sessionID)

        let data = try #require(first.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(body["model"] as? String == "hermes-agent")
        #expect(body["stream"] as? Bool == true)
        #expect(messages.last == ["role": "user", "content": "Hello"])
    }

    @Test func sendsNoExtraHeadersUnlessConfigured() throws {
        let request = try HermesSession(baseURL: base, credentials: .init(apiKey: "k")).request(for: "Hi")
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == nil)
    }

    @Test func eachCallGetsItsOwnSession() throws {
        let one = try HermesSession(baseURL: base, credentials: .init(apiKey: "k")).request(for: "Hi")
        let two = try HermesSession(baseURL: base, credentials: .init(apiKey: "k")).request(for: "Hi")
        #expect(one.value(forHTTPHeaderField: "X-Hermes-Session-Id") != two.value(forHTTPHeaderField: "X-Hermes-Session-Id"))
    }

    @Test func streamsTheReplyText() async throws {
        StubServer.replies = ["completions": (200, """
            : keepalive

            event: hermes.tool.progress
            data: {"choices":[{"delta":{"content":"🔧 web_search"}}]}

            data: {"choices":[{"delta":{"content":"It is "}}]}

            data: {"choices":[{"delta":{"content":"sunny."}}]}

            data: [DONE]

            """)]
        URLProtocol.registerClass(StubServer.self)
        defer { URLProtocol.unregisterClass(StubServer.self) }

        var text = ""
        for try await reply in try HermesSession(baseURL: base, credentials: .init(apiKey: "k")).ask("Weather?") {
            if case .text(let delta) = reply { text += delta }
        }
        #expect(text == "It is sunny.")
    }

    @Test func failsOnAnErrorStatus() async throws {
        StubServer.replies = ["completions": (401, "")]
        URLProtocol.registerClass(StubServer.self)
        defer { URLProtocol.unregisterClass(StubServer.self) }

        await #expect(throws: HermesSession.Failure.self) {
            for try await _ in try HermesSession(baseURL: base, credentials: .init(apiKey: "bad")).ask("Hi") {}
        }
    }

    /// A proxy's login redirect must fail the turn, not quietly answer with the login page.
    @Test func failsOnARedirectInsteadOfFollowingIt() async throws {
        StubServer.replies = ["completions": (302, "https://login.test/"), "": (200, "<html>Sign in</html>")]
        URLProtocol.registerClass(StubServer.self)
        defer { URLProtocol.unregisterClass(StubServer.self) }

        await #expect(throws: HermesSession.Failure.status(302)) {
            for try await _ in try HermesSession(baseURL: base, credentials: .init(apiKey: "k")).ask("Hi") {}
        }
    }
}

extension HermesSessionTests {
    @Test(.timeLimit(.minutes(1))) func tellsBackgroundWorkThatFinishesAfterTheTurnInATurnOfItsOwn() async throws {
        StubServer.replies = [
            "completions": (200, """
                event: hermes.tool.progress
                data: {"tool": "delegate_task", "status": "running"}

                event: hermes.tool.progress
                data: {"tool": "delegate_task", "status": "completed"}

                data: {"choices":[{"delta":{"content":"I've started it in the background."}}]}

                data: [DONE]

                """),
            "messages": (200, """
                {"object": "list", "data": [
                  {"id": 12, "role": "user", "content": "[ASYNC DELEGATION BATCH COMPLETE — deleg_1] Uptime: 3 days"},
                  {"id": 11, "role": "assistant", "content": "I've started it in the background."}
                ]}
                """),
        ]
        URLProtocol.registerClass(StubServer.self)
        defer { URLProtocol.unregisterClass(StubServer.self) }

        let session = HermesSession(baseURL: base, credentials: .init(apiKey: "k"), poll: .milliseconds(20))
        for try await _ in try session.ask("Check the uptime in the background") {}
        StubServer.replies["completions"] = (200, """
            data: {"choices":[{"delta":{"content":"Up for 3 days."}}]}

            data: [DONE]

            """)
        var ownTurns = session.ownTurns.makeAsyncIterator()
        let turn = try #require(await ownTurns.next())
        var told: [AgentReply] = []
        for try await reply in turn { told.append(reply) }
        #expect(told == [.text("Up for 3 days.")])
        session.stop()
        #expect(await ownTurns.next() == nil)
    }

    @Test(.timeLimit(.minutes(1))) func saysOnceWhenItCantCheckOnBackgroundWorkThenRecovers() async throws {
        StubServer.replies = [
            "completions": (200, """
                event: hermes.tool.progress
                data: {"tool": "delegate_task", "status": "running"}

                data: [DONE]

                """),
            "messages": (302, "https://login.test/"),
            "": (200, "<html>Sign in</html>"),
        ]
        URLProtocol.registerClass(StubServer.self)
        defer { URLProtocol.unregisterClass(StubServer.self) }

        let session = HermesSession(baseURL: base, credentials: .init(apiKey: "k"), poll: .milliseconds(20))
        for try await _ in try session.ask("Check the uptime in the background") {}
        var problems = session.problems.makeAsyncIterator()
        #expect(await problems.next()?.contains("302") == true)

        StubServer.replies["messages"] = (200, """
            {"data": [{"id": 3, "role": "user", "content": "[ASYNC DELEGATION BATCH COMPLETE — d] done"}]}
            """)
        var ownTurns = session.ownTurns.makeAsyncIterator()
        #expect(await ownTurns.next() != nil)
        session.stop()
        // One failure streak, one problem: the polls that failed before recovering said nothing more.
        #expect(await problems.next() == nil)
    }

    @Test func readsOnlyBackgroundResultsFromTheHistory() throws {
        let page = Data(#"{"data": [{"id": "a", "role": "user", "content": "hello"}, {"id": 7, "role": "user", "content": "[ASYNC DELEGATION BATCH COMPLETE — d]\nok"}, {"id": 8, "role": "tool", "content": "[ASYNC DELEGATION BATCH COMPLETE"}]}"#.utf8)
        let results = try HermesSession.delegationResults(in: page)
        #expect(results.map(\.id) == ["7"])
    }

    @Test func aHistoryThatIsNotHermesJSONIsAnError() {
        #expect(throws: HermesSession.Failure.self) { try HermesSession.delegationResults(in: Data("<html>Sign in</html>".utf8)) }
    }
}

/// Answers requests to `hermes.test` with a canned status and body, chosen by the last part of the path.
/// A 3xx redirects to the URL in its body, as a proxy's login page would.
final class StubServer: URLProtocol {
    nonisolated(unsafe) static var replies: [String: (status: Int, body: String)] = [:]

    private var reply: (status: Int, body: String) {
        Self.replies[request.url?.lastPathComponent ?? ""] ?? (404, "")
    }

    override class func canInit(with request: URLRequest) -> Bool { ["hermes.test", "login.test"].contains(request.url?.host) }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if (300..<400).contains(reply.status), let target = URL(string: reply.body) {
            let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Location": target.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            // A refused redirect ends here, with the 3xx as the response; a followed one loads the target instead.
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
