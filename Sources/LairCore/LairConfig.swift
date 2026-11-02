import Foundation

/// `~/.config/lair/config.json`: the agents you can call. Written with defaults on first launch.
public struct LairConfig: Codable, Equatable, Sendable {
    public var agents: [AgentConfig]
    /// After the agent speaks, listen a few seconds for your reply without a key press; unset means on.
    public var listenForAnswers: Bool?
    /// Lair shows at the top of the screen, grown out of the notch; unset means on.
    public var island: Bool?
    /// Agents on this Mac may speak and ask you things through Lair; unset means off.
    public var guests: GuestSettings?

    public init(agents: [AgentConfig]) {
        self.agents = agents
    }

    public var listensForAnswers: Bool { listenForAnswers != false }
    public var showsIsland: Bool { island != false }

    /// The agents you can call: turned-off ones keep their settings but stay out of the room.
    public var enabledAgents: [AgentConfig] { agents.filter { $0.disabled != true } }

    public static let defaultURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: ".config/lair/config.json")

    /// What a first launch writes: nobody yet, the welcome window has you pick.
    public static let initial = LairConfig(agents: [])

    /// Whether there is a config file, so a first launch can be told from the ones after it.
    public static func exists(at url: URL = defaultURL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public static func load(from url: URL = defaultURL) throws -> LairConfig {
        guard exists(at: url) else {
            try initial.save(to: url)
            return initial
        }
        return try JSONDecoder().decode(LairConfig.self, from: Data(contentsOf: url))
    }

    /// Readable on purpose: the file is meant to be edited by hand too.
    public func save(to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// A stable id for a new agent: its name in lowercase letters and digits, made unique.
    public func newAgentID(for name: String) -> String {
        let base = name.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        let stem = base.isEmpty ? "agent" : base
        var id = stem
        var suffix = 2
        while agents.contains(where: { $0.id == id }) {
            id = "\(stem)\(suffix)"
            suffix += 1
        }
        return id
    }

    /// A new agent for `label`, not yet added: a name no other agent has ("Claude", "Claude 2"…), a free id, the first
    /// of `voices` nobody uses, and the next color of the palette.
    public func newAgent(named label: String, voices: [String]) -> AgentConfig {
        let usedNames = Set(agents.map { $0.name.lowercased() })
        var name = label
        var n = 2
        while usedNames.contains(name.lowercased()) { name = "\(label) \(n)"; n += 1 }
        let usedVoices = Set(agents.map(\.voice))
        return AgentConfig(
            id: newAgentID(for: label), name: name, kind: .acp,
            voice: voices.first { !usedVoices.contains($0) } ?? "af_heart",
            color: AgentConfig.palette[agents.count % AgentConfig.palette.count])
    }
}

/// Lair's MCP server, which agents running on this Mac join as guests.
public struct GuestSettings: Codable, Equatable, Sendable {
    public var port: Int
    /// How long a guest's question waits for your answer.
    public var answerSeconds: Int
    /// A guest that has said nothing for this long leaves the room.
    public var idleMinutes: Int

    public static let standard = GuestSettings(port: 7477, answerSeconds: 120, idleMinutes: 30)

    public var url: URL { URL(string: "http://127.0.0.1:\(port)/mcp")! }

    /// Keychain item holding the bearer token agents send.
    public static let keychainService = "lair.guests"
    public static let keychainAccount = "token"
}

public struct AgentConfig: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// Started on this Mac and spoken to over the Agent Client Protocol.
        case acp
        /// A Hermes agent reached over its HTTP API, at home or away.
        case hermes
        /// An agent on this Mac that joined over MCP; never saved in the config.
        case guest
    }

    /// The avatar colors new agents take in turn.
    public static let palette = ["#D97757", "#7B5CFF", "#3FB68B", "#E5B93C", "#4BA3E3", "#E35D8F"]

    public var id: String
    public var name: String
    public var kind: Kind
    public var voice: String
    /// Avatar color, as `#RRGGBB`.
    public var color: String
    public var model: String?
    /// Working folder of the agent's sessions; `~` is your home folder.
    public var directory: String?
    /// How much the agent thinks, by the name the agent gives its levels (low, high…); unset keeps its default.
    public var thinking: String?
    /// ACP: the preset this agent is started from (`AgentPreset.id`).
    public var preset: String?
    /// ACP: the command that starts an agent that isn't a preset, e.g. `["my-agent", "--acp"]`.
    public var command: [String]?
    /// ACP: the agent's other choices to make as a call starts, by option id: e.g. `{"mode": "acceptEdits"}`.
    public var options: [String: String]?
    /// ACP: environment variables set for the agent's command, over your shell's.
    public var env: [String: String]?
    /// ACP: the ACP Registry entry this agent was added from or follows (`Registry.Entry.id`).
    public var registry: String?
    /// Hermes: base URL of its API server, e.g. `http://hermes.local:8642` at home or a public address away.
    public var url: String?
    /// Turned off: kept in the file and in Settings, but not in the panel, Mission Control or by name.
    public var disabled: Bool?
    /// Hermes: extra HTTP headers sent with every request, such as a proxy's access token.
    /// Only the names are here; the values are secrets kept in the Keychain.
    public var headers: [String]?
    /// How long spoken answers are; unset means normal.
    public var answers: Answers?

    /// How much an agent says out loud, from a line to a few sentences.
    public enum Answers: String, Codable, CaseIterable, Sendable {
        case brief, normal, detailed
    }

    public init(id: String, name: String, kind: Kind, voice: String, color: String, model: String? = nil,
                directory: String? = nil, url: String? = nil, headers: [String]? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.voice = voice
        self.color = color
        self.model = model
        self.directory = directory
        self.url = url
        self.headers = headers
    }

    public init(id: String, name: String, preset: AgentPreset, voice: String, color: String, model: String? = nil,
                directory: String? = nil) {
        self.init(id: id, name: name, kind: .acp, voice: voice, color: color, model: model, directory: directory)
        self.preset = preset.id
    }

    /// Reads configs written before agents spoke ACP: a "claude-code" or "omp" agent becomes that preset.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let legacyPresets = ["claude-code": AgentPreset.claude.id, "omp": AgentPreset.omp.id]
        let kind = try container.decode(String.self, forKey: .kind)
        self.kind = legacyPresets[kind] == nil ? try container.decode(Kind.self, forKey: .kind) : .acp
        preset = try container.decodeIfPresent(String.self, forKey: .preset) ?? legacyPresets[kind]
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        voice = try container.decode(String.self, forKey: .voice)
        color = try container.decode(String.self, forKey: .color)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        directory = try container.decodeIfPresent(String.self, forKey: .directory)
        thinking = try container.decodeIfPresent(String.self, forKey: .thinking)
        command = try container.decodeIfPresent([String].self, forKey: .command)
        options = try container.decodeIfPresent([String: String].self, forKey: .options)
        env = try container.decodeIfPresent([String: String].self, forKey: .env)
        registry = try container.decodeIfPresent(String.self, forKey: .registry)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        disabled = try container.decodeIfPresent(Bool.self, forKey: .disabled)
        headers = try container.decodeIfPresent([String].self, forKey: .headers)
        answers = try container.decodeIfPresent(Answers.self, forKey: .answers)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, voice, color, model, directory, thinking, preset, command, options, env, registry, url, disabled, headers, answers
    }

    /// What starts an ACP agent: its own command, else its preset's.
    public var launchCommand: [String]? {
        command ?? AgentPreset.withID(preset)?.command
    }

    /// The environment the agent starts with: `base` with this agent's `env` over it.
    public func launchEnvironment(over base: [String: String]?) -> [String: String]? {
        guard let env else { return base }
        return (base ?? [:]).merging(env) { _, own in own }
    }

    /// The registry entry this agent runs: the one it was added from, or its preset's.
    public var registryEntry: String? { registry ?? AgentPreset.withID(preset)?.registryID }

    /// Starts this agent from `entry`, pinned to the entry's version.
    public mutating func follow(_ entry: Registry.Entry) {
        command = entry.command
        env = entry.env.isEmpty ? nil : entry.env
        registry = entry.id
    }

    /// Keychain service holding this agent's secrets: `api-key`, and one `header:<name>` per extra header.
    public var keychainService: String { "lair.\(id)" }

    public static func headerAccount(_ name: String) -> String { "header:\(name)" }

    /// Every Keychain account this agent may use, so they can all be removed with it.
    public var secretAccounts: [String] { ["api-key"] + (headers ?? []).map(Self.headerAccount) }

    public var directoryURL: URL? {
        directory.map { URL(fileURLWithPath: NSString(string: $0).expandingTildeInPath) }
    }
}
