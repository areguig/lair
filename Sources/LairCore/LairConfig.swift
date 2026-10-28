import Foundation

/// `~/.config/lair/config.json`: the agents you can call. Written with defaults on first launch.
public struct LairConfig: Codable, Equatable, Sendable {
    public var agents: [AgentConfig]

    public init(agents: [AgentConfig]) {
        self.agents = agents
    }

    public static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".config/lair/config.json")

    public static let initial = LairConfig(agents: [
        AgentConfig(id: "claude", name: "Claude", kind: .claudeCode, voice: "af_heart", color: "#D97757",
                    model: "haiku", directory: "~"),
    ])

    public static func load(from url: URL = defaultURL) throws -> LairConfig {
        guard FileManager.default.fileExists(atPath: url.path) else {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(initial).write(to: url)
            return initial
        }
        return try JSONDecoder().decode(LairConfig.self, from: Data(contentsOf: url))
    }
}

public struct AgentConfig: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case claudeCode = "claude-code"
        case hermes
    }

    public var id: String
    public var name: String
    public var kind: Kind
    public var voice: String
    /// Avatar color, as `#RRGGBB`.
    public var color: String
    public var model: String?
    /// Working folder of the agent's sessions; `~` is your home folder.
    public var directory: String?
    /// Claude Code: `--permission-mode` for its sessions; unset keeps your own Claude Code settings.
    public var permissionMode: String?
    /// Hermes: base URL of its API server, e.g. `http://hermes.local:8642` at home or a public address away.
    public var url: String?

    public init(id: String, name: String, kind: Kind, voice: String, color: String, model: String? = nil,
                directory: String? = nil, url: String? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.voice = voice
        self.color = color
        self.model = model
        self.directory = directory
        self.url = url
    }

    /// Keychain service holding this agent's secrets: `api-key`, and optionally
    /// `cf-access-client-id` and `cf-access-client-secret`.
    public var keychainService: String { "lair.\(id)" }

    public var directoryURL: URL? {
        directory.map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) }
    }
}
