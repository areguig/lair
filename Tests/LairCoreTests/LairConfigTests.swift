import Foundation
import LairCore
import Testing

struct LairConfigTests {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "lair-\(UUID().uuidString)/config.json")
    }

    @Test func writesTheInitialConfigWhenMissing() throws {
        let url = temporaryURL()
        #expect(!LairConfig.exists(at: url))
        #expect(try LairConfig.load(from: url) == .initial)
        #expect(LairConfig.exists(at: url))
        #expect(try LairConfig.load(from: url) == .initial)
    }

    @Test func aFirstLaunchHasNoAgentsYet() {
        #expect(LairConfig.initial.agents.isEmpty)
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

    /// Configs from before ACP: their Claude Code and omp agents become those presets, keeping their settings.
    @Test func readsClaudeCodeAndOmpAgentsAsTheirPresets() throws {
        let url = temporaryURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(##"{"agents":[{"id":"c","name":"C","kind":"claude-code","voice":"v","color":"#000000","model":"opus","permissionMode":"plan"},{"id":"o","name":"O","kind":"omp","voice":"v","color":"#000000","thinking":"high"}]}"##.utf8)
            .write(to: url)
        let agents = try LairConfig.load(from: url).agents
        #expect(agents.map(\.kind) == [.acp, .acp])
        #expect(agents.map(\.preset) == ["claude", "omp"])
        #expect(agents.map(\.launchCommand) == [AgentPreset.claude.command, ["omp", "acp"]])
        #expect(agents[0].model == "opus")
        #expect(agents[1].thinking == "high")
    }

    @Test func keepsTheAgentsOtherChoices() throws {
        let url = temporaryURL()
        var agent = AgentConfig(id: "c", name: "C", preset: .claude, voice: "v", color: "#000000")
        agent.options = ["mode": "acceptEdits"]
        try LairConfig(agents: [agent]).save(to: url)
        #expect(try LairConfig.load(from: url).agents.first?.options == ["mode": "acceptEdits"])
    }

    @Test func anAgentsOwnCommandWinsOverItsPreset() {
        var agent = AgentConfig(id: "a", name: "A", kind: .acp, voice: "v", color: "#000000")
        #expect(agent.launchCommand == nil)
        agent.command = ["my-agent", "--acp"]
        #expect(agent.launchCommand == ["my-agent", "--acp"])
    }

    @Test func aPresetIsInstalledWhenItsProgramIsOnThePath() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "lair-path-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(!AgentPreset.omp.isInstalled(path: "/nowhere:\(folder.path)"))
        let program = folder.appending(path: "omp")
        FileManager.default.createFile(atPath: program.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        #expect(AgentPreset.omp.isInstalled(path: "/nowhere:\(folder.path)"))
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
        let agent = AgentConfig(id: "c", name: "C", preset: .claude, voice: "v", color: "#000000", directory: "~/dev")
        #expect(agent.directoryURL?.path == FileManager.default.homeDirectoryForCurrentUser.appending(path: "dev").path)
    }

    @Test func anOldConfigAnswersNormallyAndIsWrittenBackUnchanged() throws {
        let url = temporaryURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(##"{"agents":[{"id":"c","name":"C","kind":"acp","voice":"am_adam","color":"#000000"}]}"##.utf8).write(to: url)
        let config = try LairConfig.load(from: url)
        #expect(config.agents[0].answers == nil)
        try config.save(to: url)
        #expect(!(try String(contentsOf: url, encoding: .utf8)).contains("answers"))
    }

    @Test(arguments: AgentConfig.Answers.allCases)
    func answersSurviveASaveAndLoad(_ answers: AgentConfig.Answers) throws {
        let url = temporaryURL()
        var agent = AgentConfig(id: "c", name: "C", kind: .acp, voice: "am_adam", color: "#000000")
        agent.answers = answers
        try LairConfig(agents: [agent]).save(to: url)
        #expect(try LairConfig.load(from: url).agents[0].answers == answers)
    }
}

struct AgentRegistryFieldsTests {
    @Test func aPresetAgentRunsItsPresetsRegistryEntryUnlessAddedFromAnother() {
        var codex = AgentConfig(id: "c", name: "Codex", preset: .codex, voice: "v", color: "#000000")
        #expect(codex.registryEntry == "codex-acp")
        codex.registry = "other"
        #expect(codex.registryEntry == "other")
        let omp = AgentConfig(id: "o", name: "omp", preset: .omp, voice: "v", color: "#000000")
        #expect(omp.registryEntry == nil)
    }

    @Test func unsetFieldsAreNotWrittenAndOldConfigsReadUnchanged() throws {
        let old = Data(##"{"agents":[{"id":"c","name":"C","kind":"acp","voice":"v","color":"#000000"}]}"##.utf8)
        let config = try JSONDecoder().decode(LairConfig.self, from: old)
        #expect(config.agents[0].env == nil && config.agents[0].registry == nil)
        let written = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
        #expect(!written.contains("env") && !written.contains("registry"))
    }

    @Test func envAndRegistrySurviveASaveAndLoad() throws {
        var agent = AgentConfig(id: "c", name: "C", kind: .acp, voice: "v", color: "#000000")
        agent.env = ["A": "1"]
        agent.registry = "auggie"
        let data = try JSONEncoder().encode(LairConfig(agents: [agent]))
        #expect(try JSONDecoder().decode(LairConfig.self, from: data).agents[0] == agent)
    }

    @Test func theAgentsEnvironmentGoesOverTheShells() {
        var agent = AgentConfig(id: "c", name: "C", kind: .acp, voice: "v", color: "#000000")
        #expect(agent.launchEnvironment(over: ["PATH": "/bin"]) == ["PATH": "/bin"])
        #expect(agent.launchEnvironment(over: nil) == nil)
        agent.env = ["PATH": "/mine", "X": "1"]
        #expect(agent.launchEnvironment(over: ["PATH": "/bin", "HOME": "/h"]) == ["PATH": "/mine", "X": "1", "HOME": "/h"])
        #expect(agent.launchEnvironment(over: nil) == ["PATH": "/mine", "X": "1"])
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
        var config = LairConfig(agents: [AgentConfig(id: "claude", name: "Claude", preset: .claude, voice: "af_heart", color: "#D97757")])
        config.agents.append(AgentConfig(id: "echo", name: "Echo", kind: .hermes, voice: "bf_emma", color: "#7B5CFF",
                                         url: "http://hermes.local:8642"))
        try config.save(to: url)
        #expect(try LairConfig.load(from: url) == config)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("\"url\" : \"http://hermes.local:8642\""))
        #expect(!text.contains("permissionMode"))
    }

    @Test func givesNewAgentsUniqueReadableIDs() {
        let config = LairConfig(agents: [AgentConfig(id: "claude", name: "Claude", preset: .claude, voice: "af_heart", color: "#D97757")])
        #expect(config.newAgentID(for: "Claude") == "claude2")
        #expect(config.newAgentID(for: "My Agent!") == "myagent")
        #expect(config.newAgentID(for: "Écho") == "cho")
        #expect(config.newAgentID(for: "") == "agent")
    }
}

struct NewAgentTests {
    private let voices = ["fantine", "george", "jane"]

    @Test func firstAgentKeepsItsLabelAndTakesTheFirstVoiceAndColor() {
        let agent = LairConfig.initial.newAgent(named: "Claude", voices: voices)
        #expect(agent.name == "Claude")
        #expect(agent.id == "claude")
        #expect(agent.kind == .acp)
        #expect(agent.voice == "fantine")
        #expect(agent.color == AgentConfig.palette[0])
    }

    @Test func namesAndIDsStayUniqueEvenWhenCaseDiffers() {
        var config = LairConfig.initial
        config.agents.append(config.newAgent(named: "Claude", voices: voices))
        config.agents.append(config.newAgent(named: "claude", voices: voices))
        config.agents.append(config.newAgent(named: "Claude", voices: voices))
        #expect(config.agents.map(\.name) == ["Claude", "claude 2", "Claude 3"])
        #expect(Set(config.agents.map(\.id)).count == 3)
    }

    @Test func eachAgentGetsTheFirstVoiceNobodyUses() {
        var config = LairConfig.initial
        for _ in 0..<2 { config.agents.append(config.newAgent(named: "Codex", voices: voices)) }
        #expect(config.agents.map(\.voice) == ["fantine", "george"])
        config.agents.removeFirst()
        #expect(config.newAgent(named: "Codex", voices: voices).voice == "fantine")
    }

    @Test func fallsBackToTheDefaultVoiceWhenAllAreUsed() {
        var config = LairConfig.initial
        config.agents.append(config.newAgent(named: "A", voices: ["x"]))
        #expect(config.newAgent(named: "B", voices: ["x"]).voice == "fantine")
    }

    @Test func colorsCycleThroughThePalette() {
        var config = LairConfig.initial
        for i in 0...AgentConfig.palette.count {
            let agent = config.newAgent(named: "Agent", voices: voices)
            #expect(agent.color == AgentConfig.palette[i % AgentConfig.palette.count])
            config.agents.append(agent)
        }
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
