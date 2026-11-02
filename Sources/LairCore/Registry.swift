import Foundation

/// The ACP Registry's index: the agents anyone can add, as far as Lair can start them (npx and uvx).
public struct Registry: Decodable, Equatable, Sendable {
    public let agents: [Entry]

    /// Entries Lair can't start (a download only) are dropped, and fields it doesn't know are ignored.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        agents = try container.decode([Raw].self, forKey: .agents).compactMap(Entry.init)
    }

    private enum CodingKeys: String, CodingKey { case agents }

    public func entry(id: String?) -> Entry? {
        agents.first { $0.id == id }
    }

    /// The registry's entry for `agent` when it starts the agent differently from how `agent` does.
    public func update(for agent: AgentConfig) -> Entry? {
        guard let entry = entry(id: agent.registryEntry),
              entry.command != agent.launchCommand else { return nil }
        return entry
    }

    /// The version pinned in a command Lair builds: `npx -y pkg@1.2.3` or `uvx pkg==1.2.3`; nil when unpinned.
    public static func pinnedVersion(in command: [String]?) -> String? {
        guard let package = command?.dropFirst().first(where: { !$0.hasPrefix("-") }) else { return nil }
        if let range = package.range(of: "==") { return String(package[range.upperBound...]) }
        guard let at = package.lastIndex(of: "@"), at != package.startIndex else { return nil }
        return String(package[package.index(after: at)...])
    }

    public struct Entry: Equatable, Identifiable, Sendable {
        public let id: String
        public let name: String
        public let version: String
        public let description: String
        public let license: String
        public let website: URL?
        /// A 16 point SVG.
        public let icon: URL?
        /// What starts it, exactly as it will be saved: `["npx", "-y", "pkg@1.2.3", "--acp"]`.
        public let command: [String]
        public let env: [String: String]
        /// What must be installed for the command to run, and where to get it.
        public let needs: String
        public let installURL: URL

        /// The program of the command, to look for on the PATH.
        public var program: String { command[0] }

        fileprivate init?(_ raw: Raw) {
            if let npx = raw.distribution.npx {
                command = ["npx", "-y", npx.package] + (npx.args ?? [])
                env = npx.env ?? [:]
                needs = "Node.js"
                installURL = URL(string: "https://nodejs.org")!
            } else if let uvx = raw.distribution.uvx {
                command = ["uvx", uvx.package] + (uvx.args ?? [])
                env = uvx.env ?? [:]
                needs = "uv"
                installURL = URL(string: "https://docs.astral.sh/uv")!
            } else {
                return nil
            }
            id = raw.id
            name = raw.name
            version = raw.version
            description = raw.description
            license = raw.license
            website = raw.website.flatMap(URL.init(string:))
            icon = raw.icon.flatMap(URL.init(string:))
        }
    }

    fileprivate struct Raw: Decodable {
        let id, name, version, description, license: String
        let website, icon: String?
        let distribution: Distribution
    }

    fileprivate struct Distribution: Decodable {
        let npx, uvx: Runner?
    }

    fileprivate struct Runner: Decodable {
        let package: String
        let args: [String]?
        let env: [String: String]?
    }
}
