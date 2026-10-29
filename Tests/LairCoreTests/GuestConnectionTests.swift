import Foundation
import LairCore
import Testing

@Suite struct GuestConnectionTests {
    private let folder = FileManager.default.temporaryDirectory.appending(path: "lair-guests-\(UUID().uuidString)")
    private let url = URL(string: "http://127.0.0.1:7477/mcp")!

    private func json(_ file: URL) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
    }

    @Test func ompKeepsTheOtherServersAndSettings() throws {
        let file = folder.appending(path: "mcp.json")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"mcpServers":{"memory":{"command":"mem","args":["serve"]}},"other":true}"#.utf8).write(to: file)
        let omp = GuestConnection.Omp(file: file)
        #expect(!omp.isConnected)
        try omp.connect(url: url, token: "t0k", answerSeconds: 120)
        #expect(omp.isConnected)
        let servers = try json(file)["mcpServers"] as! [String: [String: Any]]
        #expect(servers["memory"]?["command"] as? String == "mem")
        #expect(servers["lair"]?["url"] as? String == "http://127.0.0.1:7477/mcp")
        #expect(servers["lair"]?["type"] as? String == "http")
        #expect((servers["lair"]?["headers"] as? [String: String])?["Authorization"] == "Bearer t0k")
        #expect(servers["lair"]?["timeout"] as? Int == 150_000)
        #expect(try json(file)["other"] as? Bool == true)
        try omp.disconnect()
        #expect(!omp.isConnected)
        #expect((try json(file)["mcpServers"] as! [String: Any]).keys.sorted() == ["memory"])
    }

    @Test func ompStartsTheFileWhenThereIsNone() throws {
        let omp = GuestConnection.Omp(file: folder.appending(path: "agent/mcp.json"))
        try omp.connect(url: url, token: "t0k", answerSeconds: 60)
        #expect(omp.isConnected)
        try omp.disconnect()
        try omp.disconnect()
        #expect(!omp.isConnected)
    }

    /// A stand-in CLI that records its arguments and knows whether `lair` was added.
    private func fakeClaude() throws -> (GuestConnection.ClaudeCode, URL) {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let log = folder.appending(path: "calls.txt"), state = folder.appending(path: "added")
        let script = folder.appending(path: "claude")
        try """
            #!/bin/sh
            echo "$@" >> '\(log.path)'
            case "$2" in
              get) [ -f '\(state.path)' ] || { echo "No MCP server named lair"; exit 1; } ;;
              add) touch '\(state.path)' ;;
              remove) [ -f '\(state.path)' ] || { echo "No MCP server found with name: lair"; exit 1; }
                      rm -f '\(state.path)' ;;
            esac
            """.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return (GuestConnection.ClaudeCode(command: script.path, environment: ["PATH": "/usr/bin:/bin"]), log)
    }

    @Test func claudeCodeAddsLairAtUserScope() async throws {
        let (claude, log) = try fakeClaude()
        #expect(await !claude.isConnected())
        try await claude.connect(url: url, token: "t0k")
        #expect(await claude.isConnected())
        let calls = try String(contentsOf: log, encoding: .utf8).split(separator: "\n")
        #expect(calls.contains("mcp add --scope user --transport http lair http://127.0.0.1:7477/mcp --header Authorization: Bearer t0k"))
        try await claude.disconnect()
        #expect(await !claude.isConnected())
    }

    @Test func claudeCodeReplacesAnOlderEntry() async throws {
        let (claude, log) = try fakeClaude()
        try await claude.connect(url: url, token: "old")
        try await claude.connect(url: url, token: "new")
        let calls = try String(contentsOf: log, encoding: .utf8).split(separator: "\n")
        #expect(calls.filter { $0.hasPrefix("mcp remove") }.count == 1)
        #expect(calls.last?.hasSuffix("Bearer new") == true)
    }

    @Test func aFailingCommandSaysWhy() async throws {
        let (claude, _) = try fakeClaude()
        await #expect(throws: GuestConnection.Failure.self) { try await claude.disconnect() }
        let missing = GuestConnection.ClaudeCode(command: "no-such-claude", environment: ["PATH": "/usr/bin:/bin"])
        await #expect(throws: (any Error).self) { try await missing.connect(url: url, token: "t") }
    }
}
