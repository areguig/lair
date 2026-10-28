import Foundation
import LairCore
import Testing

struct LairConfigTests {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "lair-\(UUID().uuidString)/config.json")
    }

    @Test func writesTheInitialConfigWhenMissing() throws {
        let url = temporaryURL()
        #expect(try LairConfig.load(from: url) == .initial)
        #expect(try LairConfig.load(from: url) == .initial)
    }

    @Test func readsAgentsWithOptionalFields() throws {
        let url = temporaryURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(##"{"agents":[{"id":"c","name":"C","kind":"claude-code","voice":"am_adam","color":"#000000"}]}"##.utf8)
            .write(to: url)
        let agent = try #require(try LairConfig.load(from: url).agents.first)
        #expect(agent.voice == "am_adam")
        #expect(agent.model == nil)
        #expect(agent.directoryURL == nil)
    }

    @Test func expandsTildeInTheDirectory() {
        let agent = AgentConfig(id: "c", name: "C", kind: .claudeCode, voice: "v", color: "#000000", directory: "~/dev")
        #expect(agent.directoryURL?.path == FileManager.default.homeDirectoryForCurrentUser.appending(path: "dev").path)
    }
}

struct AgentLogTests {
    @Test func readsTheFirstLineOfAnAgentsLog() throws {
        let id = "test-\(UUID().uuidString)"
        let url = AgentLog.url(for: id)
        defer { try? FileManager.default.removeItem(at: url) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "No default model selected.\n\nMore help.\n".write(to: url, atomically: true, encoding: .utf8)
        #expect(AgentLog.firstLine(for: id) == "No default model selected.")
        #expect(AgentLog.firstLine(for: "missing-\(UUID().uuidString)") == nil)
    }
}
