import Foundation
@testable import LairMCP
import MCP
import Testing

private actor FakeHost: GuestHost {
    var heard: [String] = []
    var guests: [Guest] = []
    var gone: [Guest] = []
    let answer: String?

    init(answer: String? = nil) {
        self.answer = answer
    }

    func speak(_ text: String, from guest: Guest) {
        guests.append(guest)
        heard.append("\(guest.name): \(text)")
    }

    func ask(_ question: String, from guest: Guest) -> String? {
        heard.append("\(guest.name) asks: \(question)")
        return answer
    }

    func left(_ guest: Guest) { gone.append(guest) }
}

@Suite struct GuestServerTests {
    private static let token = "test-token"

    /// A real MCP client over HTTP, as an agent would connect.
    private func connect(to host: FakeHost, path: String = "mcp", token: String = token,
                         client: Client = Client(name: "test", version: "1"))
        async throws -> (Client, HTTPClientTransport, Task<Void, Error>) {
        let port = Int.random(in: 40_000...50_000)
        let server = Task { try await GuestServer(host: host, token: Self.token).run(port: port) }
        let url = URL(string: "http://127.0.0.1:\(port)/\(path)")!
        for _ in 0..<50 {
            let transport = HTTPClientTransport(endpoint: url, requestModifier: {
                var request = $0
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return request
            })
            do {
                _ = try await client.connect(transport: transport)
                return (client, transport, server)
            } catch let error as MCPError where "\(error)".contains("401") || "\(error)".contains("token") {
                server.cancel()
                throw error
            } catch {
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        server.cancel()
        throw MCPError.connectionClosed
    }

    private func text(_ content: [Tool.Content]) -> String {
        content.compactMap { if case .text(let text, _, _) = $0 { text } else { nil } }.joined()
    }

    @Test func offersSpeakAndAsk() async throws {
        let (client, _, server) = try await connect(to: FakeHost())
        defer { server.cancel() }
        #expect(try await client.listTools().tools.map(\.name) == ["speak", "ask"])
    }

    @Test func tellsAgentsWhenToSpeakAndAsk() async throws {
        let client = Client(name: "test", version: "1")
        let port = Int.random(in: 40_000...50_000)
        let server = Task { try await GuestServer(host: FakeHost(), token: Self.token).run(port: port) }
        defer { server.cancel() }
        let transport = HTTPClientTransport(endpoint: URL(string: "http://127.0.0.1:\(port)/mcp")!, requestModifier: {
            var request = $0
            request.setValue("Bearer \(Self.token)", forHTTPHeaderField: "Authorization")
            return request
        })
        var result: Initialize.Result?
        for _ in 0..<50 where result == nil {
            result = try? await client.connect(transport: transport)
            if result == nil { try await Task.sleep(for: .milliseconds(100)) }
        }
        #expect(result?.instructions?.contains("`ask`") == true)
    }

    @Test func refusesAClientWithoutTheToken() async throws {
        await #expect(throws: (any Error).self) {
            let (_, _, server) = try await connect(to: FakeHost(), token: "wrong")
            server.cancel()
        }
    }

    @Test func speakReachesTheHostAsTheClientNamesItself() async throws {
        let host = FakeHost()
        let (client, _, server) = try await connect(to: host, client: Client(name: "claude-code", version: "2"))
        defer { server.cancel() }
        let (content, isError) = try await client.callTool(name: "speak", arguments: ["text": " Tests pass. "])
        #expect(isError == false)
        #expect(text(content) == "Said.")
        #expect(await host.heard == ["Claude Code: Tests pass."])
    }

    @Test func thePathNamesTheGuest() async throws {
        let host = FakeHost()
        let (client, _, server) = try await connect(to: host, path: "mcp/Atlas")
        defer { server.cancel() }
        _ = try await client.callTool(name: "speak", arguments: ["text": "Hi."])
        #expect(await host.heard == ["Atlas: Hi."])
    }

    /// Asking a real client for its roots is checked live with Claude Code and omp: the SDK's own client drops its
    /// stream for server requests whenever a POST stream closes empty, so it loses them at random.
    @Test func theFolderIsTheFirstFileRoot() {
        #expect(GuestServer.folder(in: [Root(uri: "https://example.com"), Root(uri: "file:///Users/me/dev/lair")])?.path
            == "/Users/me/dev/lair")
        #expect(GuestServer.folder(in: []) == nil)
    }

    @Test func aSlowClientDoesntHoldUpTheCall() async {
        let start = ContinuousClock.now
        let result = await GuestServer.within(.milliseconds(100)) {
            try await withUnsafeThrowingContinuation { (_: UnsafeContinuation<Int, Error>) in }
        }
        #expect(result == nil)
        #expect(ContinuousClock.now - start < .seconds(1))
    }

    @Test func twoSessionsAreTwoGuests() async throws {
        let host = FakeHost()
        let (first, transport, server) = try await connect(to: host)
        defer { server.cancel() }
        let second = Client(name: "test", version: "1")
        _ = try await second.connect(transport: HTTPClientTransport(endpoint: await transport.endpoint, requestModifier: {
            var request = $0
            request.setValue("Bearer \(Self.token)", forHTTPHeaderField: "Authorization")
            return request
        }))
        _ = try await first.callTool(name: "speak", arguments: ["text": "One."])
        _ = try await second.callTool(name: "speak", arguments: ["text": "Two."])
        #expect(Set(await host.guests.map(\.id)).count == 2)
    }

    @Test func endingTheSessionLeavesTheRoom() async throws {
        let host = FakeHost()
        let (client, transport, server) = try await connect(to: host)
        defer { server.cancel() }
        _ = try await client.callTool(name: "speak", arguments: ["text": "Bye."])
        var request = URLRequest(url: await transport.endpoint)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(Self.token)", forHTTPHeaderField: "Authorization")
        request.setValue(await transport.sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        request.setValue(Version.latest, forHTTPHeaderField: "MCP-Protocol-Version")
        _ = try await URLSession.shared.data(for: request)
        #expect(await host.gone.map(\.name) == ["test"])
    }

    @Test func askReturnsTheAnswer() async throws {
        let (client, _, server) = try await connect(to: FakeHost(answer: "Ship it"))
        defer { server.cancel() }
        let (content, _) = try await client.callTool(name: "ask", arguments: ["question": "Ship or wait?"])
        #expect(text(content) == "Ship it")
    }

    @Test func askSaysWhenNobodyAnswered() async throws {
        let (client, _, server) = try await connect(to: FakeHost())
        defer { server.cancel() }
        let (content, _) = try await client.callTool(name: "ask", arguments: ["question": "Ship or wait?"])
        #expect(text(content) == "The user didn't answer.")
    }

    @Test func emptyTextIsAnError() async throws {
        let (client, _, server) = try await connect(to: FakeHost())
        defer { server.cancel() }
        let (_, isError) = try await client.callTool(name: "speak", arguments: ["text": "  "])
        #expect(isError == true)
    }

    @Test func namesFollowTheClient() {
        #expect(Guest.name(path: nil, client: .init(name: "claude-code", version: "1")) == "Claude Code")
        #expect(Guest.name(path: nil, client: .init(name: "omp-coding-agent", version: "1")) == "omp")
        #expect(Guest.name(path: nil, client: .init(name: "codex", version: "1", title: "Codex")) == "Codex")
        #expect(Guest.name(path: nil, client: .init(name: "zed", version: "1")) == "zed")
        #expect(Guest.name(path: "Atlas", client: .init(name: "claude-code", version: "1")) == "Atlas")
    }
}
