import Foundation
import LairCore
import Testing

struct RegistryTests {
    /// Real entries, trimmed: npx with env, uvx with env, a download only, both, no website, and a field no one knows.
    private let index = ##"""
    {"version":"1.0.0","somethingNew":true,"agents":[
    {"id":"auggie","name":"Auggie CLI","version":"0.36.0","description":"Augment Code's software agent","repository":"https://github.com/augmentcode/auggie","website":"https://www.augmentcode.com/","authors":["Augment Code"],"license":"proprietary","icon":"https://cdn.agentclientprotocol.com/registry/v1/latest/auggie.svg","distribution":{"npx":{"package":"@augmentcode/auggie@0.36.0","args":["--acp"],"env":{"AUGMENT_DISABLE_AUTO_UPDATE":"1"}}}},
    {"id":"fast-agent","name":"fast-agent","version":"0.10.1","description":"Code and build agents","repository":"https://github.com/evalstate/fast-agent","website":"https://fast-agent.ai","authors":["fast-agent"],"license":"Apache 2.0","distribution":{"uvx":{"package":"fast-agent-acp==0.10.1","args":["-x"],"env":{"FAST_AGENT_MODEL":"codexplan"}}},"icon":"https://cdn.agentclientprotocol.com/registry/v1/latest/fast-agent.svg"},
    {"id":"amp-acp","name":"Amp","version":"0.12.0","description":"ACP wrapper for Amp","repository":"https://github.com/tao12345666333/amp-acp","authors":["tao"],"license":"Apache-2.0","icon":"https://cdn.agentclientprotocol.com/registry/v1/latest/amp-acp.svg","distribution":{"binary":{"darwin-aarch64":{"archive":"https://example.com/amp.tar.gz","cmd":"./amp-acp"}}}},
    {"id":"kilo","name":"Kilo","version":"7.8.18","description":"The open source coding agent","repository":"https://github.com/Kilo-Org/kilocode","website":"https://kilo.ai/","authors":["Kilo Code"],"license":"MIT","icon":"https://cdn.agentclientprotocol.com/registry/v1/latest/kilo.svg","distribution":{"binary":{"darwin-aarch64":{"archive":"https://example.com/kilo.zip","cmd":"./kilo","args":["acp"]}},"npx":{"package":"@kilocode/cli@7.8.18","args":["acp"]}}},
    {"id":"claude-acp","name":"Claude Agent","version":"0.99.1","description":"ACP wrapper for Anthropic's Claude","repository":"https://github.com/agentclientprotocol/claude-agent-acp","authors":["Anthropic"],"license":"proprietary","distribution":{"npx":{"package":"@agentclientprotocol/claude-agent-acp@0.99.1"}},"icon":"https://cdn.agentclientprotocol.com/registry/v1/latest/claude-acp.svg"}
    ]}
    """##

    private func registry() throws -> Registry {
        try JSONDecoder().decode(Registry.self, from: Data(index.utf8))
    }

    @Test func keepsOnlyWhatNpxAndUvxCanStart() throws {
        #expect(try registry().agents.map(\.id) == ["auggie", "fast-agent", "kilo", "claude-acp"])
    }

    @Test func buildsAnNpxCommandWithItsArgumentsAndEnvironment() throws {
        let entry = try #require(try registry().entry(id: "auggie"))
        #expect(entry.command == ["npx", "-y", "@augmentcode/auggie@0.36.0", "--acp"])
        #expect(entry.env == ["AUGMENT_DISABLE_AUTO_UPDATE": "1"])
        #expect(entry.version == "0.36.0")
        #expect(entry.program == "npx")
        #expect(entry.needs == "Node.js")
        #expect(entry.installURL.host() == "nodejs.org")
    }

    @Test func buildsAUvxCommandThatNeedsUv() throws {
        let entry = try #require(try registry().entry(id: "fast-agent"))
        #expect(entry.command == ["uvx", "fast-agent-acp==0.10.1", "-x"])
        #expect(entry.env == ["FAST_AGENT_MODEL": "codexplan"])
        #expect(entry.needs == "uv")
        #expect(entry.installURL.host() == "docs.astral.sh")
    }

    @Test func anEntryWithBothRunsThroughNpx() throws {
        #expect(try registry().entry(id: "kilo")?.command == ["npx", "-y", "@kilocode/cli@7.8.18", "acp"])
    }

    @Test func readsTheTextsAndLinks() throws {
        let entry = try #require(try registry().entry(id: "auggie"))
        #expect(entry.name == "Auggie CLI")
        #expect(entry.license == "proprietary")
        #expect(entry.website == URL(string: "https://www.augmentcode.com/"))
        #expect(entry.icon?.lastPathComponent == "auggie.svg")
        #expect(try registry().entry(id: "claude-acp")?.website == nil)
        #expect(try registry().entry(id: "claude-acp")?.env == [:])
    }

    @Test func readsThePinnedVersionOfACommand() {
        #expect(Registry.pinnedVersion(in: ["npx", "-y", "@augmentcode/auggie@0.35.0", "--acp"]) == "0.35.0")
        #expect(Registry.pinnedVersion(in: ["npx", "-y", "cline@3.0.74"]) == "3.0.74")
        #expect(Registry.pinnedVersion(in: ["uvx", "fast-agent-acp==0.10.1", "-x"]) == "0.10.1")
        #expect(Registry.pinnedVersion(in: ["npx", "-y", "@scope/pkg"]) == nil)
        #expect(Registry.pinnedVersion(in: ["copilot", "--acp"]) == nil)
        #expect(Registry.pinnedVersion(in: nil) == nil)
    }

    @Test func offersAnUpdateWhenTheRegistryStartsTheAgentDifferently() throws {
        var agent = AgentConfig(id: "a", name: "A", kind: .acp, voice: "v", color: "#000000")
        agent.registry = "auggie"
        agent.command = ["npx", "-y", "@augmentcode/auggie@0.35.0", "--acp"]
        #expect(try registry().update(for: agent)?.version == "0.36.0")
        agent.follow(try #require(try registry().entry(id: "auggie")))
        #expect(try registry().update(for: agent) == nil)
    }

    @Test func followingAnEntryPinsItsCommandAndEnvironment() throws {
        var agent = AgentConfig(id: "a", name: "A", kind: .acp, voice: "v", color: "#000000")
        agent.follow(try #require(try registry().entry(id: "fast-agent")))
        #expect(agent.command == ["uvx", "fast-agent-acp==0.10.1", "-x"])
        #expect(agent.env == ["FAST_AGENT_MODEL": "codexplan"])
        #expect(agent.registry == "fast-agent")
        agent.follow(try #require(try registry().entry(id: "claude-acp")))
        #expect(agent.env == nil)
    }

    @Test func aPresetInTheRegistryGetsUpdatesToo() throws {
        var agent = AgentConfig(id: "c", name: "C", preset: .claude, voice: "v", color: "#000000")
        #expect(AgentPreset.claude.registryID == "claude-acp")
        #expect(AgentPreset.codex.registryID == "codex-acp")
        #expect(AgentPreset.copilot.registryID == nil)
        #expect(try registry().update(for: agent) == nil)
        agent.command = ["npx", "-y", "@agentclientprotocol/claude-agent-acp@0.90.0"]
        #expect(try registry().update(for: agent)?.version == "0.99.1")
    }

    @Test func anAgentOutsideTheRegistryNeverUpdates() throws {
        let agent = AgentConfig(id: "c", name: "C", preset: .copilot, voice: "v", color: "#000000")
        #expect(try registry().update(for: agent) == nil)
    }
}
