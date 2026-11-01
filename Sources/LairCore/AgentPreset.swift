import Foundation

/// The agents Lair knows how to start over the Agent Client Protocol. A preset agent keeps only the preset's id in
/// the config, so a new Lair brings its tested command along.
public struct AgentPreset: Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let command: [String]
    /// What must be installed for the command to run, and where to get it.
    public let needs: String
    public let installURL: URL
    /// How the agent's own sessions introduce themselves when they join Lair over MCP.
    public let mcpClientName: String?

    public static let all: [AgentPreset] = [claude, codex, copilot, opencode, omp, hermes]

    // Adapters run through npx at the version tested with Lair.
    public static let claude = AgentPreset(
        id: "claude", name: "Claude", command: ["npx", "-y", "@agentclientprotocol/claude-agent-acp@0.99.1"],
        needs: "Node.js", installURL: URL(string: "https://nodejs.org")!, mcpClientName: "claude-code")
    public static let codex = AgentPreset(
        id: "codex", name: "Codex", command: ["npx", "-y", "@agentclientprotocol/codex-acp@2.5.0"],
        needs: "Node.js", installURL: URL(string: "https://nodejs.org")!, mcpClientName: nil)
    public static let copilot = AgentPreset(
        id: "copilot", name: "Copilot", command: ["copilot", "--acp"],
        needs: "GitHub Copilot CLI", installURL: URL(string: "https://github.com/github/copilot-cli")!, mcpClientName: nil)
    public static let opencode = AgentPreset(
        id: "opencode", name: "opencode", command: ["opencode", "acp"],
        needs: "opencode", installURL: URL(string: "https://opencode.ai")!, mcpClientName: nil)
    public static let omp = AgentPreset(
        id: "omp", name: "omp", command: ["omp", "acp"],
        needs: "omp", installURL: URL(string: "https://github.com/can1357/oh-my-pi")!, mcpClientName: "omp-coding-agent")
    public static let hermes = AgentPreset(
        id: "hermes", name: "Hermes", command: ["hermes", "acp"],
        needs: "Hermes Agent", installURL: URL(string: "https://github.com/NousResearch/hermes-agent")!, mcpClientName: nil)

    public static func withID(_ id: String?) -> AgentPreset? {
        all.first { $0.id == id }
    }

    /// Whether the command's program is in one of `path`'s folders, as `/usr/bin/env` will look for it.
    public func isInstalled(path: String?) -> Bool {
        guard let program = command.first else { return false }
        return (path ?? "").split(separator: ":").contains { folder in
            FileManager.default.isExecutableFile(atPath: "\(folder)/\(program)")
        }
    }
}
