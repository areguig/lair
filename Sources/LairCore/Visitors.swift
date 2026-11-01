import Foundation

/// Sessions you start yourself on this Mac: which of your agents each one is, and what to call the rest.
public enum Visitors {
    /// The tool a session runs, from the name its MCP client gives itself.
    public static func preset(ofClient name: String?) -> AgentPreset? {
        name.flatMap { name in AgentPreset.all.first { $0.mcpClientName == name } }
    }

    /// The agent with this session's tool and exactly its folder; a parent folder doesn't count, or an agent in `~`
    /// would claim every session.
    public static func agent(client: String?, folder: URL?, in agents: [AgentConfig]) -> AgentConfig? {
        guard let preset = preset(ofClient: client), let folder else { return nil }
        let path = canonical(folder)
        return agents.first { $0.preset == preset.id && $0.directoryURL.map(canonical) == path }
    }

    /// "Checkout", then "Checkout (1)", "Checkout (2)", the way the Mac names copies.
    public static func name(_ base: String, taken: Set<String>) -> String {
        guard taken.contains(base) else { return base }
        var n = 1
        while taken.contains("\(base) (\(n))") { n += 1 }
        return "\(base) (\(n))"
    }

    /// A new agent's name from its folder: `checkout-api` → "Checkout api".
    public static func agentName(for folder: URL) -> String {
        let words = folder.lastPathComponent.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    /// `~/dev/app` under your home folder, the full path elsewhere: how the config file writes folders.
    public static func configPath(_ folder: URL) -> String {
        let home = canonical(FileManager.default.homeDirectoryForCurrentUser), path = canonical(folder)
        return path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    /// Symlinks resolved, so `/tmp/x` and `/private/tmp/x` are the same folder.
    static func canonical(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }
}
