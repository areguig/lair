import Foundation

/// Going on with a call in the agent's own CLI, in a terminal, and back to voice when the CLI quits.
public enum KeyboardHandoff {
    /// Where the CLI opens: Terminal comes with macOS; herdr when you have it and chose it.
    public enum Terminal: String, Codable, Sendable, CaseIterable {
        case terminal, herdr
    }

    /// The CLI line that picks the session up; nil for agents whose CLI isn't known to share its sessions with ACP.
    public static func command(preset: String?, sessionID: String) -> [String]? {
        switch preset {
        case "claude": ["claude", "--resume", sessionID]
        case "codex": ["codex", "resume", sessionID]
        default: nil
        }
    }

    /// Who comes back to voice: opened as `lair://back?agent=…&session=…` when the CLI quits.
    public struct Back: Equatable, Sendable {
        public let agent: String
        public let sessionID: String

        public init(agent: String, sessionID: String) {
            (self.agent, self.sessionID) = (agent, sessionID)
        }

        public var url: URL {
            var components = URLComponents()
            components.scheme = "lair"
            components.host = "back"
            components.queryItems = [.init(name: "agent", value: agent), .init(name: "session", value: sessionID)]
            return components.url!
        }

        public init?(url: URL) {
            guard url.scheme == "lair", url.host() == "back",
                  let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
                  let agent = items.first(where: { $0.name == "agent" })?.value,
                  let session = items.first(where: { $0.name == "session" })?.value
            else { return nil }
            (self.agent, self.sessionID) = (agent, session)
        }
    }

    /// What the terminal runs: the CLI in the agent's folder with your login PATH. Quitting it, or closing the
    /// window, opens `back`.
    public static func script(command: [String], folder: String, path: String?, back: Back) -> String {
        var lines = [
            "#!/bin/sh",
            "# Lair: quitting the CLI gives the conversation back to Lair's voice.",
            "back=\(quote(back.url.absoluteString))",
            #"trap '/usr/bin/open -g "$back"' EXIT"#,
            "trap 'exit' HUP INT TERM",
        ]
        if let path { lines.append("export PATH=\(quote(path))") }
        lines.append("cd \(quote(folder)) || exit 1")
        lines.append(command.map(quote).joined(separator: " "))
        return lines.joined(separator: "\n") + "\n"
    }

    /// How `terminal` is asked to run the script at `file`.
    public static func launch(_ file: URL, in terminal: Terminal, title: String, folder: String) -> [String] {
        switch terminal {
        case .terminal:
            return ["/usr/bin/open", "-a", "Terminal", file.path]
        case .herdr:
            let tab: [String: Any] = ["name": title, "folder": folder, "argv": ["/bin/sh", file.path]]
            let data = try! JSONSerialization.data(withJSONObject: tab, options: [.sortedKeys, .withoutEscapingSlashes])
            let json = String(decoding: data, as: UTF8.self)
            return ["/usr/bin/env", "herdr-app", "do", "tab.new", json]
        }
    }

    static func quote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }
}
