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

    @Test func keepsHeaderNamesInTheConfigAndValuesInTheKeychain() throws {
        let url = temporaryURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(##"{"agents":[{"id":"h","name":"H","kind":"hermes","voice":"v","color":"#000000","headers":["X-Token"]}]}"##.utf8)
            .write(to: url)
        let agent = try #require(try LairConfig.load(from: url).agents.first)
        #expect(agent.headers == ["X-Token"])
        #expect(agent.secretAccounts == ["api-key", "header:X-Token"])
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

struct LairConfigSavingTests {
    @Test func savesAndReadsBackTheSameConfig() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "lair-\(UUID().uuidString)/config.json")
        var config = LairConfig.initial
        config.agents.append(AgentConfig(id: "sage", name: "Sage", kind: .hermes, voice: "bf_emma", color: "#7B5CFF",
                                         url: "http://hermes.local:8642"))
        try config.save(to: url)
        #expect(try LairConfig.load(from: url) == config)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("\"url\" : \"http://hermes.local:8642\""))
        #expect(!text.contains("permissionMode"))
    }

    @Test func givesNewAgentsUniqueReadableIDs() {
        let config = LairConfig.initial
        #expect(config.newAgentID(for: "Claude") == "claude2")
        #expect(config.newAgentID(for: "My Agent!") == "myagent")
        #expect(config.newAgentID(for: "Écho") == "cho")
        #expect(config.newAgentID(for: "") == "agent")
    }
}

struct KeychainTests {
    @Test func storesReplacesAndRemovesASecret() throws {
        let service = "lair.test-\(UUID().uuidString)"
        defer { Keychain.delete(service: service, account: "api-key") }
        try Keychain.setPassword("first", service: service, account: "api-key")
        try Keychain.setPassword("second", service: service, account: "api-key")
        #expect(Keychain.password(service: service, account: "api-key") == "second")
        try Keychain.setPassword("", service: service, account: "api-key")
        #expect(Keychain.password(service: service, account: "api-key") == nil)
    }
}

struct DisabledAgentTests {
    private func config(_ agents: String) throws -> LairConfig {
        try JSONDecoder().decode(LairConfig.self, from: Data(#"{"agents":[\#(agents)]}"#.utf8))
    }

    @Test func turnedOffAgentsStayInTheFileButOutOfTheRoom() throws {
        let config = try config(#"{"id":"a","name":"A","kind":"omp","voice":"af_heart","color":"red"},"#
            + #"{"id":"b","name":"B","kind":"omp","voice":"af_heart","color":"red","disabled":true}"#)
        #expect(config.agents.map(\.id) == ["a", "b"])
        #expect(config.enabledAgents.map(\.id) == ["a"])
    }

    @Test func anAgentIsOnUnlessTurnedOff() throws {
        let config = try config(#"{"id":"a","name":"A","kind":"omp","voice":"af_heart","color":"red"}"#)
        #expect(config.agents[0].disabled == nil)
        #expect(config.enabledAgents.count == 1)
    }
}
