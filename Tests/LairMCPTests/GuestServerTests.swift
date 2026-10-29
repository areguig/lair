import Foundation
import LairMCP
import MCP
import Testing

private actor FakeHost: GuestHost {
    var heard: [String] = []
    let answer: String?

    init(answer: String?) {
        self.answer = answer
    }

    func speak(_ text: String, from guest: String) { heard.append("\(guest): \(text)") }

    func ask(_ question: String, from guest: String) -> String? {
        heard.append("\(guest) asks: \(question)")
        return answer
    }
}

@Suite struct GuestServerTests {
    /// A real MCP client over HTTP, as an agent would connect.
    private func connect(to host: FakeHost, as guest: String) async throws -> (Client, Task<Void, Error>) {
        let port = Int.random(in: 40_000...50_000)
        let server = Task { try await GuestServer(host: host).run(port: port) }
        let client = Client(name: "test", version: "1")
        let url = URL(string: "http://127.0.0.1:\(port)/mcp/\(guest)")!
        for _ in 0..<50 {
            if (try? await client.connect(transport: HTTPClientTransport(endpoint: url))) != nil { return (client, server) }
            try await Task.sleep(for: .milliseconds(100))
        }
        server.cancel()
        throw MCPError.connectionClosed
    }

    private func text(_ content: [Tool.Content]) -> String {
        content.compactMap { if case .text(let text, _, _) = $0 { text } else { nil } }.joined()
    }

    @Test func offersSpeakAndAsk() async throws {
        let (client, server) = try await connect(to: FakeHost(answer: nil), as: "Atlas")
        defer { server.cancel() }
        #expect(try await client.listTools().tools.map(\.name) == ["speak", "ask"])
    }

    @Test func speakReachesTheHostUnderTheGuestsName() async throws {
        let host = FakeHost(answer: nil)
        let (client, server) = try await connect(to: host, as: "Atlas")
        defer { server.cancel() }
        let (content, isError) = try await client.callTool(name: "speak", arguments: ["text": "Tests pass."])
        #expect(isError == false)
        #expect(text(content) == "Said.")
        #expect(await host.heard == ["Atlas: Tests pass."])
    }

    @Test func askReturnsTheSpokenAnswer() async throws {
        let (client, server) = try await connect(to: FakeHost(answer: "Ship it"), as: "Atlas")
        defer { server.cancel() }
        let (content, _) = try await client.callTool(name: "ask", arguments: ["question": "Ship or wait?"])
        #expect(text(content) == "Ship it")
    }

    @Test func askSaysWhenNobodyAnswered() async throws {
        let (client, server) = try await connect(to: FakeHost(answer: nil), as: "Atlas")
        defer { server.cancel() }
        let (content, _) = try await client.callTool(name: "ask", arguments: ["question": "Ship or wait?"])
        #expect(text(content) == "The user didn't answer.")
    }

    @Test func emptyTextIsAnError() async throws {
        let (client, server) = try await connect(to: FakeHost(answer: nil), as: "Atlas")
        defer { server.cancel() }
        let (_, isError) = try await client.callTool(name: "speak", arguments: ["text": ""])
        #expect(isError == true)
    }
}
